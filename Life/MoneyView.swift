import SwiftUI

// MARK: - MoneyView

struct MoneyView: View {

    @Environment(AppState.self) private var appState
    @State private var showAddBill = false
    @State private var showAddIncome = false
    @State private var showAddOneOff = false
    @State private var editingBill: Bill? = nil
    @State private var editingIncome: Income? = nil
    @State private var editingOneOff: OneOffExpense? = nil

    private var currencySymbol: String { appState.moneySettings.currency.symbol }

    private var monthlyBillsTotal: Double {
        appState.bills.reduce(0) { $0 + $1.amount }
    }

    private var monthlyIncomeTotal: Double {
        appState.incomes.reduce(0) { $0 + $1.amount }
    }

    private var oneOffThisMonth: [OneOffExpense] {
        let cal = Calendar.current
        return appState.oneOffExpenses.filter { cal.isDate($0.date, equalTo: Date(), toGranularity: .month) }
    }

    private var oneOffThisMonthTotal: Double {
        oneOffThisMonth.reduce(0) { $0 + $1.amount }
    }

    private var netThisMonth: Double {
        monthlyIncomeTotal - monthlyBillsTotal - oneOffThisMonthTotal
    }

    private var billsByDay: [Int: [Bill]] {
        Dictionary(grouping: appState.bills, by: \.dayOfMonth)
    }

    private var sortedBills: [Bill] {
        appState.bills.sorted { $0.dayOfMonth < $1.dayOfMonth }
    }

    private var sortedIncomes: [Income] {
        appState.incomes.sorted { $0.dayOfMonth < $1.dayOfMonth }
    }

    private var sortedOneOff: [OneOffExpense] {
        appState.oneOffExpenses.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
                // Monthly summary card
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Net This Month")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text(currencySymbol)
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.2f", netThisMonth))
                                .font(.largeTitle.bold())
                                .foregroundColor(netThisMonth >= 0 ? .primary : .red)
                        }
                        HStack(spacing: 16) {
                            summaryStat(label: "Income", value: monthlyIncomeTotal, color: .green)
                            summaryStat(label: "Bills", value: monthlyBillsTotal, color: .red)
                            if oneOffThisMonthTotal > 0 {
                                summaryStat(label: "One-Off", value: oneOffThisMonthTotal, color: .orange)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Mini calendar
                Section("Calendar") {
                    MonthCalendarView(billsByDay: billsByDay)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color(.secondarySystemGroupedBackground))
                }

                // Bills list
                Section("Bills") {
                    if sortedBills.isEmpty {
                        EmptyStateView(icon: "creditcard", title: "No bills yet", subtitle: "Add your first recurring bill.")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(sortedBills) { bill in
                            BillRow(bill: bill, currencySymbol: currencySymbol)
                                .contentShape(Rectangle())
                                .onTapGesture { editingBill = bill }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                appState.deleteBill(id: sortedBills[index].id)
                            }
                        }
                    }
                }

                // Income list
                Section("Income") {
                    if sortedIncomes.isEmpty {
                        EmptyStateView(icon: "banknote", title: "No income yet", subtitle: "Add your salary or other recurring income.")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(sortedIncomes) { income in
                            IncomeRow(income: income, currencySymbol: currencySymbol)
                                .contentShape(Rectangle())
                                .onTapGesture { editingIncome = income }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                appState.deleteIncome(id: sortedIncomes[index].id)
                            }
                        }
                    }
                }

                // One-off expenses
                Section("One-Off Expenses") {
                    if sortedOneOff.isEmpty {
                        EmptyStateView(icon: "cart", title: "No one-off expenses", subtitle: "Log a purchase that isn't a recurring bill.")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(sortedOneOff) { expense in
                            OneOffExpenseRow(expense: expense, currencySymbol: currencySymbol)
                                .contentShape(Rectangle())
                                .onTapGesture { editingOneOff = expense }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                appState.deleteOneOffExpense(id: sortedOneOff[index].id)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Money")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showAddBill = true } label: { Label("Add Bill", systemImage: "creditcard") }
                        Button { showAddIncome = true } label: { Label("Add Income", systemImage: "banknote") }
                        Button { showAddOneOff = true } label: { Label("Add One-Off Expense", systemImage: "cart") }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
        .sheet(isPresented: $showAddBill) { AddBillSheet() }
        .sheet(isPresented: $showAddIncome) { AddIncomeSheet() }
        .sheet(isPresented: $showAddOneOff) { AddOneOffExpenseSheet() }
        .sheet(item: $editingBill) { bill in AddBillSheet(editing: bill) }
        .sheet(item: $editingIncome) { income in AddIncomeSheet(editing: income) }
        .sheet(item: $editingOneOff) { expense in AddOneOffExpenseSheet(editing: expense) }
    }

    private func summaryStat(label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(currencySymbol)\(String(format: "%.0f", value))")
                .font(.subheadline.bold())
                .foregroundColor(color)
        }
    }
}

// MARK: - Bill Row

private struct BillRow: View {
    let bill: Bill
    let currencySymbol: String

    private var daysUntilDue: Int {
        let cal = Calendar.current
        let today = cal.component(.day, from: Date())
        let currentMonth = cal.component(.month, from: Date())
        let currentYear = cal.component(.year, from: Date())

        var components = DateComponents()
        components.year = currentYear
        components.month = currentMonth
        components.day = bill.dayOfMonth

        guard let dueDate = cal.date(from: components) else { return 0 }

        if bill.dayOfMonth < today {
            // Next month
            guard let nextMonth = cal.date(byAdding: .month, value: 1, to: dueDate) else { return 0 }
            return cal.dateComponents([.day], from: Date(), to: nextMonth).day ?? 0
        }

        return cal.dateComponents([.day], from: Date(), to: dueDate).day ?? 0
    }

    @ViewBuilder
    private var dueLabel: some View {
        let days = daysUntilDue
        if days == 0 {
            Text("Due today")
                .font(.caption)
                .foregroundColor(.red)
        } else if days <= 3 {
            Text("Due in \(days) days")
                .font(.caption)
                .foregroundColor(.orange)
        } else {
            Text("Due in \(days) days")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(bill.name)
                    .font(.subheadline)
                HStack(spacing: 6) {
                    Text("Day \(bill.dayOfMonth)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("·")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    dueLabel
                }
            }
            Spacer()
            Text("\(currencySymbol)\(String(format: "%.2f", bill.amount))")
                .font(.subheadline.bold())
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Income Row

private struct IncomeRow: View {
    let income: Income
    let currencySymbol: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(income.name)
                    .font(.subheadline)
                Text("Day \(income.dayOfMonth)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(currencySymbol)\(String(format: "%.2f", income.amount))")
                .font(.subheadline.bold())
                .foregroundColor(.green)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - One-Off Expense Row

private struct OneOffExpenseRow: View {
    let expense: OneOffExpense
    let currencySymbol: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.name)
                    .font(.subheadline)
                Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(currencySymbol)\(String(format: "%.2f", expense.amount))")
                .font(.subheadline.bold())
                .foregroundColor(.orange)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Month Calendar

private struct MonthCalendarView: View {

    let billsByDay: [Int: [Bill]]

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    private var cal: Calendar { Calendar.current }
    private var today: Date { Date() }

    private var firstDayOfMonth: Date {
        let comps = cal.dateComponents([.year, .month], from: today)
        return cal.date(from: comps) ?? today
    }

    private var firstWeekday: Int {
        // 0-indexed (0 = Sunday)
        (cal.component(.weekday, from: firstDayOfMonth) - 1)
    }

    private var daysInMonth: Int {
        cal.range(of: .day, in: .month, for: today)?.count ?? 30
    }

    private var todayDay: Int {
        cal.component(.day, from: today)
    }

    var body: some View {
        VStack(spacing: 6) {
            // Header
            Text(today.formatted(.dateTime.month(.wide).year()))
                .font(.subheadline.bold())
                .padding(.top, 12)

            // Day labels
            HStack {
                ForEach(dayLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)

            // Day grid
            LazyVGrid(columns: columns, spacing: 6) {
                // Empty leading cells
                ForEach(0..<firstWeekday, id: \.self) { _ in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                }
                // Day cells
                ForEach(1...daysInMonth, id: \.self) { day in
                    DayCell(
                        day: day,
                        isToday: day == todayDay,
                        bills: billsByDay[day] ?? []
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
    }
}

private struct DayCell: View {
    let day: Int
    let isToday: Bool
    let bills: [Bill]

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if isToday {
                    Circle()
                        .fill(AppTheme.primary)
                        .frame(width: 28, height: 28)
                }
                Text("\(day)")
                    .font(isToday ? .caption.bold() : .caption)
                    .foregroundColor(isToday ? .white : .primary)
            }

            if !bills.isEmpty {
                Circle()
                    .fill(Color.red)
                    .frame(width: 5, height: 5)
            } else {
                Color.clear.frame(width: 5, height: 5)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Add Bill Sheet

struct AddBillSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var editing: Bill? = nil

    @State private var name = ""
    @State private var amountText = ""
    @State private var dayOfMonth = 1
    @State private var notes = ""
    @FocusState private var isNameFocused: Bool

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && Double(amountText.replacingOccurrences(of: ",", with: ".")) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill") {
                    TextField("Name (e.g. Rent)", text: $name)
                        .focused($isNameFocused)
                    HStack {
                        Text(appState.moneySettings.currency.symbol)
                            .foregroundColor(.secondary)
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Schedule") {
                    Stepper("Day of month: \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes)
                }

                if let editing {
                    Section {
                        Button("Delete Bill", role: .destructive) {
                            appState.deleteBill(id: editing.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "New Bill" : "Edit Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") {
                        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return }
                        let trimmedName = name.trimmingCharacters(in: .whitespaces)
                        if let editing {
                            appState.updateBill(id: editing.id, name: trimmedName, amount: amount, dayOfMonth: dayOfMonth, notes: notes)
                        } else {
                            appState.addBill(name: trimmedName, amount: amount, dayOfMonth: dayOfMonth, notes: notes)
                        }
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let editing {
                    name = editing.name
                    amountText = editing.amount.formatted1
                    dayOfMonth = editing.dayOfMonth
                    notes = editing.notes
                } else {
                    isNameFocused = true
                }
            }
        }
    }
}

// MARK: - Add Income Sheet

struct AddIncomeSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var editing: Income? = nil

    @State private var name = ""
    @State private var amountText = ""
    @State private var dayOfMonth = 1
    @State private var notes = ""
    @FocusState private var isNameFocused: Bool

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && Double(amountText.replacingOccurrences(of: ",", with: ".")) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Income") {
                    TextField("Name (e.g. Salary)", text: $name)
                        .focused($isNameFocused)
                    HStack {
                        Text(appState.moneySettings.currency.symbol)
                            .foregroundColor(.secondary)
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Schedule") {
                    Stepper("Day of month: \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes)
                }

                if let editing {
                    Section {
                        Button("Delete Income", role: .destructive) {
                            appState.deleteIncome(id: editing.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "New Income" : "Edit Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") {
                        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return }
                        let trimmedName = name.trimmingCharacters(in: .whitespaces)
                        if let editing {
                            appState.updateIncome(id: editing.id, name: trimmedName, amount: amount, dayOfMonth: dayOfMonth, notes: notes)
                        } else {
                            appState.addIncome(name: trimmedName, amount: amount, dayOfMonth: dayOfMonth, notes: notes)
                        }
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let editing {
                    name = editing.name
                    amountText = editing.amount.formatted1
                    dayOfMonth = editing.dayOfMonth
                    notes = editing.notes
                } else {
                    isNameFocused = true
                }
            }
        }
    }
}

// MARK: - Add One-Off Expense Sheet

struct AddOneOffExpenseSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var editing: OneOffExpense? = nil

    @State private var name = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var notes = ""
    @FocusState private var isNameFocused: Bool

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && Double(amountText.replacingOccurrences(of: ",", with: ".")) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Expense") {
                    TextField("Name (e.g. New shoes)", text: $name)
                        .focused($isNameFocused)
                    HStack {
                        Text(appState.moneySettings.currency.symbol)
                            .foregroundColor(.secondary)
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes)
                }

                if let editing {
                    Section {
                        Button("Delete Expense", role: .destructive) {
                            appState.deleteOneOffExpense(id: editing.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "New Expense" : "Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") {
                        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return }
                        let trimmedName = name.trimmingCharacters(in: .whitespaces)
                        if let editing {
                            appState.updateOneOffExpense(id: editing.id, name: trimmedName, amount: amount, date: date, notes: notes)
                        } else {
                            appState.addOneOffExpense(name: trimmedName, amount: amount, date: date, notes: notes)
                        }
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let editing {
                    name = editing.name
                    amountText = editing.amount.formatted1
                    date = editing.date
                    notes = editing.notes
                } else {
                    isNameFocused = true
                }
            }
        }
    }
}
