import SwiftUI

// MARK: - MoneyView

struct MoneyView: View {

    @Environment(AppState.self) private var appState
    @State private var showAddBill = false

    private var monthlyTotal: Double {
        appState.bills.reduce(0) { $0 + $1.amount }
    }

    private var currentMonthDays: [Int] {
        let cal = Calendar.current
        let range = cal.range(of: .day, in: .month, for: Date())
        return Array(range ?? (1..<31))
    }

    private var billsByDay: [Int: [Bill]] {
        Dictionary(grouping: appState.bills, by: \.dayOfMonth)
    }

    private var sortedBills: [Bill] {
        appState.bills.sorted { $0.dayOfMonth < $1.dayOfMonth }
    }

    var body: some View {
        List {
                // Monthly total card
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monthly Outgoings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text("£")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.2f", monthlyTotal))
                                .font(.largeTitle.bold())
                        }
                        Text("\(appState.bills.count) bills")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                if sortedBills.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "creditcard")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text("No bills yet")
                                .font(.headline)
                            Text("Tap + to add your first bill.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section("Bills") {
                        ForEach(sortedBills) { bill in
                            BillRow(bill: bill)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                appState.deleteBill(id: sortedBills[index].id)
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
                    Button {
                        showAddBill = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
        .sheet(isPresented: $showAddBill) {
            AddBillSheet()
        }
    }
}

// MARK: - Bill Row

private struct BillRow: View {
    let bill: Bill

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
            Text("£\(String(format: "%.2f", bill.amount))")
                .font(.subheadline.bold())
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
                        .fill(Color(hex: "#30d158"))
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

    @State private var name = ""
    @State private var amountText = ""
    @State private var dayOfMonth = 1
    @State private var notes = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill") {
                    TextField("Name (e.g. Rent)", text: $name)
                        .focused($isNameFocused)
                    HStack {
                        Text("£")
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
            }
            .navigationTitle("New Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
                              let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return }
                        appState.addBill(name: name.trimmingCharacters(in: .whitespaces), amount: amount, dayOfMonth: dayOfMonth, notes: notes)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Double(amountText.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
            .onAppear { isNameFocused = true }
        }
    }
}
