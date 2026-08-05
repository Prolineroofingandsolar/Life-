import SwiftUI
import Charts

// MARK: - Body View

struct BodyView: View {

    @Environment(AppState.self) private var appState
    @State private var selectedTab: BodyTab = .weight

    enum BodyTab: String, CaseIterable, Identifiable {
        case weight = "Weight"
        case composition = "Composition"
        case measurements = "Measures"
        case lifts = "Lifts"
        var id: String { rawValue }

        /// Spoken instead of the segment's own text. "Measures" is a truncation
        /// that fits the segment, not a word anyone would say, and "Lifts" out
        /// of context gives no clue what the tab contains.
        var accessibilityLabel: String {
            switch self {
            case .weight:       return "Weight"
            case .composition:  return "Body composition"
            case .measurements: return "Body measurements"
            case .lifts:        return "Lift records"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented picker. Each segment is separately named for
            // VoiceOver — the control announced itself as "Tab" and its
            // segments not at all, so there was no way to tell which of the
            // four was selected or what the others were.
            Picker("Tab", selection: $selectedTab) {
                ForEach(BodyTab.allCases) { tab in
                    Text(tab.rawValue)
                        .tag(tab)
                        .accessibilityLabel(tab.accessibilityLabel)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .accessibilityLabel("Body section")
            .accessibilityValue(selectedTab.accessibilityLabel)

            // Content
            switch selectedTab {
            case .weight:       WeightTab()
            case .composition:  CompositionTab()
            case .measurements: MeasurementsTab()
            case .lifts:        LiftsTab()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Body")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Weight Tab

private struct WeightTab: View {

    @Environment(AppState.self) private var appState
    @State private var weightInput = ""
    @State private var weightDate = Date()
    @FocusState private var isWeightFocused: Bool
    @State private var chartRange: ChartRange = .month
    @State private var goalInput = ""
    @FocusState private var isGoalFocused: Bool

    /// The accepted range expressed in whatever unit the field is showing, so
    /// the hint quotes bounds the user can compare against what they typed.
    private var weightRangeForUnit: ClosedRange<Double> {
        let range = BodyMetricLimits.weightKg
        guard unit != .kg else { return range }
        let low = WeightUnit.kg.convert(range.lowerBound, to: unit)
        let high = WeightUnit.kg.convert(range.upperBound, to: unit)
        return low...high
    }

    /// The typed weight in kilograms, or nil if it isn't a usable number.
    ///
    /// Validated in the display unit and converted afterwards, so the bounds
    /// mean the same thing whichever unit is selected. Zero, negative values,
    /// and the `Double`-parseable strings "nan" and "inf" are all rejected here
    /// — each of them used to be stored, and a single zero drags the whole
    /// weight chart to the floor.
    private var parsedWeightEntry: Double? {
        BodyMetricLimits.parse(weightInput, in: weightRangeForUnit)
            .map { unit.convert($0, to: .kg) }
    }

    private var parsedGoalWeight: Double? {
        BodyMetricLimits.parse(goalInput, in: weightRangeForUnit)
            .map { unit.convert($0, to: .kg) }
    }

    enum ChartRange: String, CaseIterable {
        case week = "W"
        case month = "1M"
        case threeMonth = "3M"
        case all = "All"

        var days: Int? {
            switch self {
            case .week:       return 7
            case .month:      return 30
            case .threeMonth: return 90
            case .all:        return nil
            }
        }
    }

    private var unit: WeightUnit { appState.workoutSettings.weightUnit }

    private var entries: [WeightEntry] {
        appState.weightEntries.sorted { $0.date < $1.date }
    }

    private var displayEntries: [(date: Date, value: Double)] {
        let cutoff: Date? = chartRange.days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
        return entries.compactMap { entry in
            if let cutoff, entry.date < cutoff { return nil }
            let val = unit == .kg ? entry.valueKg : WeightUnit.kg.convert(entry.valueKg, to: .lbs)
            return (entry.date, val)
        }
    }

    private var currentWeight: Double? {
        entries.map { unit == .kg ? $0.valueKg : WeightUnit.kg.convert($0.valueKg, to: .lbs) }.last
    }

    private var goalWeightDisplay: Double? {
        appState.workoutSettings.goalWeightKg.map { WeightUnit.kg.convert($0, to: unit) }
    }

    private var xAxisStride: Calendar.Component {
        switch chartRange {
        case .week:       return .day
        case .month:      return .weekOfYear
        case .threeMonth: return .month
        case .all:        return .month
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch chartRange {
        case .week:  return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day()
        default:     return .dateTime.month(.abbreviated)
        }
    }

    var body: some View {
        List {
            // Current weight card
            if let current = currentWeight {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Weight")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(current.weightDisplay)
                                .font(.largeTitle.bold())
                            Text(unit.label)
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Chart
            if displayEntries.count > 1 {
                Section {
                    // Range picker
                    Picker("Range", selection: $chartRange) {
                        ForEach(ChartRange.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)

                    Chart {
                        ForEach(Array(displayEntries.enumerated()), id: \.offset) { _, entry in
                            LineMark(
                                x: .value("Date", entry.date),
                                y: .value("Weight", entry.value)
                            )
                            .foregroundStyle(AppTheme.primary)
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Date", entry.date),
                                y: .value("Weight", entry.value)
                            )
                            .foregroundStyle(AppTheme.primary.opacity(0.1))
                            .interpolationMethod(.catmullRom)
                        }
                        if let goal = goalWeightDisplay {
                            RuleMark(y: .value("Goal", goal))
                                .foregroundStyle(.orange)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .annotation(position: .top, alignment: .leading) {
                                    Text("Goal: \(goal.weightDisplay) \(unit.label)")
                                        .font(.caption2.bold())
                                        .foregroundColor(.orange)
                                }
                        }
                    }
                    .frame(height: 200)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: xAxisStride)) { _ in
                            AxisValueLabel(format: xAxisFormat)
                        }
                    }
                }
            }

            // Log new weight
            Section("Log Weight") {
                // A weigh-in you forgot to record on the day used to be
                // unloggable: every entry was stamped with `Date()`, so a
                // Monday weight entered on Wednesday landed on Wednesday and
                // sat in the chart at the wrong point. The date defaults to now,
                // so the common case is still one field and a button.
                DatePicker(
                    "Date",
                    selection: $weightDate,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .accessibilityLabel("Date and time of this weigh-in")

                HStack {
                    TextField("e.g. 75.5", text: $weightInput)
                        .keyboardType(.decimalPad)
                        .focused($isWeightFocused)
                        .accessibilityLabel("Weight in \(unit.label)")
                    Text(unit.label)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    Button("Add") {
                        guard let value = parsedWeightEntry else { return }
                        appState.logBodyWeight(valueKg: value, date: weightDate)
                        weightInput = ""
                        weightDate = Date()
                        isWeightFocused = false
                    }
                    .buttonStyle(.borderless)
                    .disabled(parsedWeightEntry == nil)
                    .accessibilityLabel("Add weight entry")
                }

                // Shown only once something has been typed, so an empty form
                // isn't nagging about a value nobody has entered yet.
                if !weightInput.isEmpty, parsedWeightEntry == nil {
                    Text(BodyMetricLimits.rangeHint(weightRangeForUnit, unit: unit.label))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            // Goal weight
            Section("Goal Weight") {
                HStack {
                    TextField(goalWeightDisplay.map { $0.weightDisplay } ?? "None set", text: $goalInput)
                        .keyboardType(.decimalPad)
                        .focused($isGoalFocused)
                        .accessibilityLabel("Goal weight in \(unit.label)")
                    Text(unit.label)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    Button("Save") {
                        guard let value = parsedGoalWeight else { return }
                        appState.setGoalWeight(kg: value)
                        goalInput = ""
                        isGoalFocused = false
                    }
                    .buttonStyle(.borderless)
                    // A goal weight of 0 was accepted and then divided into, so
                    // the progress bar read as complete the moment it was set.
                    // It's held to the same range as any other weight.
                    .disabled(parsedGoalWeight == nil)
                    .accessibilityLabel("Save goal weight")
                }
                if !goalInput.isEmpty, parsedGoalWeight == nil {
                    Text(BodyMetricLimits.rangeHint(weightRangeForUnit, unit: unit.label))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                if goalWeightDisplay != nil {
                    Button("Clear Goal", role: .destructive) {
                        appState.setGoalWeight(kg: nil)
                    }
                    .accessibilityLabel("Clear goal weight")
                }
            }

            // History
            if !entries.isEmpty {
                Section("History") {
                    ForEach(entries.reversed()) { entry in
                        let displayValue = unit == .kg ? entry.valueKg : WeightUnit.kg.convert(entry.valueKg, to: .lbs)
                        HStack {
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                .foregroundColor(.secondary)
                            Spacer()
                            // `weightDisplay` rather than `formatted1`: the
                            // latter drops the decimal on whole numbers, so a
                            // stored 75.0 and a stored 75.04 both printed as
                            // "75" and the column had a ragged edge. Full
                            // precision is stored; one fixed decimal is shown.
                            Text("\(displayValue.weightDisplay) \(unit.label)")
                                .font(.subheadline)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(displayValue.weightDisplay) \(unit.label) on \(entry.date.formatted(date: .abbreviated, time: .omitted))")
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                appState.deleteWeightEntry(id: entry.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Composition Tab

private enum CompMetric: String, CaseIterable, Identifiable {
    case bodyFat = "Body Fat"
    case leanMass = "Lean Mass"
    case bmi = "BMI"
    var id: String { rawValue }
}

private struct CompositionTab: View {

    @Environment(AppState.self) private var appState
    @State private var selectedMetric: CompMetric = .bodyFat
    @State private var showAddEntry = false

    /// Where the Apple Health import has got to.
    ///
    /// The import used to have exactly two visible states: a spinner, and a
    /// permission-denied message. Everything else was silent. Granting access
    /// and importing nothing looked identical to granting access and importing
    /// a year of readings — the spinner stopped and the screen didn't change —
    /// and a query that threw looked the same again. Each outcome now says
    /// which one it was.
    enum ImportState: Equatable {
        case idle
        case requestingPermission
        case loading
        case imported(entries: Int, weights: Int)
        case empty
        case permissionDenied
        case unavailable
        case failed(String)
    }

    @State private var importState: ImportState = .idle

    @State private var healthKitManager = HealthKitManager()

    private var entries: [BodyCompEntry] {
        appState.bodyCompEntries.sorted { $0.date < $1.date }
    }

    private var chartData: [(date: Date, value: Double)] {
        entries.compactMap { entry in
            let val: Double?
            switch selectedMetric {
            case .bodyFat: val = entry.bodyFatPct
            case .leanMass: val = entry.leanMassKg
            case .bmi: val = entry.bmi
            }
            guard let v = val else { return nil }
            return (entry.date, v)
        }
    }

    private var latestEntry: BodyCompEntry? { entries.last }

    var body: some View {
        List {
            // Latest values
            if let latest = latestEntry {
                Section {
                    if let bf = latest.bodyFatPct {
                        InfoRow(label: "Body Fat", value: "\((bf * 100).percentDisplay)%")
                    }
                    if let lm = latest.leanMassKg {
                        InfoRow(label: "Lean Mass", value: "\(lm.weightDisplay) kg")
                    }
                    if let bmi = latest.bmi {
                        InfoRow(label: "BMI", value: bmi.weightDisplay)
                    }
                } header: {
                    Text("Latest")
                }
            }

            // Import button
            Section {
                Button {
                    importFromHealthKit()
                } label: {
                    HStack {
                        Label("Import from \(HealthProvider.appleHealth.displayName)", systemImage: HealthProvider.appleHealth.iconName)
                            .foregroundColor(.red)
                        Spacer()
                        if isImporting {
                            ProgressView()
                                .accessibilityLabel(importStatusText ?? "Importing")
                        }
                    }
                }
                .disabled(isImporting)
                .accessibilityLabel("Import from \(HealthProvider.appleHealth.displayName)")
                .accessibilityHint(isImporting ? "Import in progress" : "Reads weight, body fat, lean mass and BMI")

                if let status = importStatusText {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(importStatusColour)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    showAddEntry = true
                } label: {
                    Label("Log Manually", systemImage: "pencil")
                        .foregroundColor(AppTheme.primary)
                }
                .accessibilityLabel("Log body composition manually")
            }

            // Chart
            if chartData.count > 1 {
                Section {
                    Picker("Metric", selection: $selectedMetric) {
                        ForEach(CompMetric.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Chart {
                        ForEach(Array(chartData.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value(selectedMetric.rawValue, point.value)
                            )
                            .foregroundStyle(.blue)
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .frame(height: 180)
                }
            }

            // History
            if !entries.isEmpty {
                Section("History") {
                    ForEach(entries.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack(spacing: 16) {
                                if let bf = entry.bodyFatPct {
                                    Text("BF: \(String(format: "%.1f%%", bf * 100))")
                                        .font(.caption)
                                }
                                if let lm = entry.leanMassKg {
                                    Text("LM: \(lm.weightDisplay) kg")
                                        .font(.caption)
                                }
                                if let bmi = entry.bmi {
                                    Text("BMI: \(bmi.weightDisplay)")
                                        .font(.caption)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                appState.deleteBodyCompEntry(id: entry.id)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showAddEntry) {
            AddBodyCompSheet()
        }
    }

    private var isImporting: Bool {
        importState == .requestingPermission || importState == .loading
    }

    /// One line describing whatever the import is doing or last did.
    private var importStatusText: String? {
        switch importState {
        case .idle:
            return nil
        case .requestingPermission:
            return "Asking \(HealthProvider.appleHealth.displayName) for permission…"
        case .loading:
            return "Reading the last year from \(HealthProvider.appleHealth.displayName)…"
        case .imported(let entries, let weights):
            var parts: [String] = []
            if weights > 0 { parts.append("\(weights) weight \(weights == 1 ? "entry" : "entries")") }
            if entries > 0 { parts.append("\(entries) composition \(entries == 1 ? "entry" : "entries")") }
            return "Imported " + parts.joined(separator: " and ") + "."
        case .empty:
            // The most confusing outcome of the lot, and the one that used to
            // show nothing at all: permission was granted and the import
            // genuinely worked, there was simply nothing on the other end.
            return "\(HealthProvider.appleHealth.displayName) returned no body data for the last year. Check that your scale or tracker writes weight and body fat into the Health app."
        case .permissionDenied:
            return "\(HealthProvider.appleHealth.displayName) access was refused. Allow it under Settings ▸ Health ▸ Data Access & Devices ▸ Life."
        case .unavailable:
            return "\(HealthProvider.appleHealth.displayName) isn't available on this device."
        case .failed(let message):
            return "Import failed: \(message)"
        }
    }

    private var importStatusColour: Color {
        switch importState {
        case .imported:                            return .green
        case .permissionDenied, .failed:           return .red
        case .empty, .unavailable:                 return .orange
        case .idle, .loading, .requestingPermission: return .secondary
        }
    }

    private func importFromHealthKit() {
        guard HealthKitManager.isHealthDataAvailable else {
            importState = .unavailable
            return
        }

        importState = .requestingPermission
        Task {
            let granted = await healthKitManager.requestPermissions()
            guard granted else {
                await MainActor.run { importState = .permissionDenied }
                return
            }

            await MainActor.run { importState = .loading }

            let data = await healthKitManager.importBodyData(daysBack: 365)

            var entryMap: [String: BodyCompEntry] = [:]

            // Weight goes to WeightEntry. Counted rather than assumed: readings
            // outside a plausible range are refused by `logBodyWeight`, and the
            // summary should report what was actually stored.
            var storedWeights = 0
            for (date, kg) in data.weight {
                let stored = await MainActor.run {
                    appState.logBodyWeight(valueKg: kg, date: date, source: .appleHealth)
                }
                if stored { storedWeights += 1 }
            }

            for (date, pct) in data.bodyFat {
                let key = date.dayKey
                var entry = entryMap[key] ?? BodyCompEntry(date: date)
                entry.bodyFatPct = pct
                entry.source = HealthProvider.appleHealth.storageValue
                entryMap[key] = entry
            }

            for (date, kg) in data.leanMass {
                let key = date.dayKey
                var entry = entryMap[key] ?? BodyCompEntry(date: date)
                entry.leanMassKg = kg
                entry.source = HealthProvider.appleHealth.storageValue
                entryMap[key] = entry
            }

            for (date, val) in data.bmi {
                let key = date.dayKey
                var entry = entryMap[key] ?? BodyCompEntry(date: date)
                entry.bmi = val
                entry.source = HealthProvider.appleHealth.storageValue
                entryMap[key] = entry
            }

            let newEntries = entryMap.values.filter {
                $0.bodyFatPct != nil || $0.leanMassKg != nil || $0.bmi != nil
            }
            await MainActor.run {
                appState.mergeBodyCompEntries(Array(newEntries))
                importState = (newEntries.isEmpty && storedWeights == 0)
                    ? .empty
                    : .imported(entries: newEntries.count, weights: storedWeights)
            }
        }
    }
}

// MARK: - Add Body Composition Sheet

private struct AddBodyCompSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var bodyFatText = ""
    @State private var bmiText = ""

    /// Body fat as the stored 0–1 fraction.
    ///
    /// A body fat of 150% used to be accepted and stored as 1.5, which then
    /// rendered as "150.0%" and skewed every average it was included in. It's
    /// held to a real percentage.
    private var bodyFatPct: Double? {
        BodyMetricLimits.parse(bodyFatText, in: BodyMetricLimits.bodyFatPercent)
            .map { $0 / 100 }
    }

    /// BMI must be positive and finite. A negative BMI was storable and drew a
    /// line below the axis; `Double("-5")` parses perfectly well.
    private var bmi: Double? {
        BodyMetricLimits.parse(bmiText, in: BodyMetricLimits.bmi)
    }

    /// Save is enabled only when at least one field holds a value that is both
    /// present and valid — an out-of-range number is not a reason to enable it.
    private var canSave: Bool { bodyFatPct != nil || bmi != nil }

    private var bodyFatIsInvalid: Bool { !bodyFatText.isEmpty && bodyFatPct == nil }
    private var bmiIsInvalid: Bool { !bmiText.isEmpty && bmi == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                Section("Body Composition") {
                    HStack {
                        Text("Body Fat")
                        Spacer()
                        TextField("0", text: $bodyFatText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .accessibilityLabel("Body fat percentage")
                        Text("%").foregroundColor(.secondary).accessibilityHidden(true)
                    }
                    if bodyFatIsInvalid {
                        Text(BodyMetricLimits.rangeHint(BodyMetricLimits.bodyFatPercent, unit: "%"))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    HStack {
                        Text("BMI")
                        Spacer()
                        TextField("0", text: $bmiText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .accessibilityLabel("BMI")
                    }
                    if bmiIsInvalid {
                        Text(BodyMetricLimits.rangeHint(BodyMetricLimits.bmi, unit: ""))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            .navigationTitle("Log Body Composition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Both actions are real buttons in their standard placements,
                // so VoiceOver announces them as buttons with the right labels
                // and reports Save's disabled state. Save was previously
                // indistinguishable from Cancel to a screen reader.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel")
                        .accessibilityHint("Discards this entry")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var entry = BodyCompEntry(date: date)
                        entry.bodyFatPct = bodyFatPct
                        entry.bmi = bmi
                        entry.source = HealthProvider.manual.storageValue
                        appState.mergeBodyCompEntries([entry])
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityLabel("Save")
                    .accessibilityHint(canSave
                        ? "Saves this body composition entry"
                        : "Enter a valid body fat percentage or BMI first")
                }
            }
        }
    }
}

// MARK: - Lifts Tab

private struct LiftPRItem: Identifiable {
    let id: String
    let exercise: Exercise
    let pr: AppState.PRResult
}

private struct LiftsTab: View {

    @Environment(AppState.self) private var appState

    private var prItems: [LiftPRItem] {
        appState.exercises
            .map { exercise in
                let pr = appState.computePRs(for: exercise.id)
                return LiftPRItem(id: exercise.id, exercise: exercise, pr: pr)
            }
            .filter { $0.pr.best1RM > 0 }
            .sorted { $0.pr.best1RM > $1.pr.best1RM }
    }

    private var muscles: [String] {
        Array(Set(prItems.map(\.exercise.muscle))).sorted()
    }

    private func items(for muscle: String) -> [LiftPRItem] {
        prItems.filter { $0.exercise.muscle == muscle }
            .sorted { $0.pr.best1RM > $1.pr.best1RM }
    }

    var body: some View {
        List {
            if prItems.isEmpty {
                Section {
                    EmptyStateView(icon: "dumbbell", title: "No lift records yet", subtitle: "Complete workouts to see your PRs here.")
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(muscles, id: \.self) { muscle in
                    Section {
                        ForEach(items(for: muscle)) { item in
                            PRRow(item: item)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Circle().fill(muscle.muscleColor).frame(width: 10, height: 10)
                            Text(muscle)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct PRRow: View {
    @Environment(AppState.self) private var appState
    let item: LiftPRItem

    private var unit: WeightUnit { appState.workoutSettings.weightUnit }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.exercise.name)
                    .font(.subheadline)
                Text("\(WeightUnit.kg.convert(item.pr.bestWeight, to: unit).formatted1) \(unit.label.lowercased()) × \(item.pr.bestReps)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("e1RM")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(WeightUnit.kg.convert(item.pr.best1RM, to: unit).formatted1) \(unit.label.lowercased())")
                    .font(.subheadline.bold())
                    .foregroundColor(AppTheme.primary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Measurements Tab (P3.2)

private enum MeasurementMetric: String, CaseIterable, Identifiable {
    case waist = "Waist"
    case chest = "Chest"
    case hips = "Hips"
    case leftArm = "L. Arm"
    case rightArm = "R. Arm"
    case leftThigh = "L. Thigh"
    case rightThigh = "R. Thigh"
    case neck = "Neck"
    case shoulders = "Shoulders"
    var id: String { rawValue }

    func value(from m: BodyMeasurement) -> Double? {
        switch self {
        case .waist:      return m.waistCm
        case .chest:      return m.chestCm
        case .hips:       return m.hipsCm
        case .leftArm:    return m.leftArmCm
        case .rightArm:   return m.rightArmCm
        case .leftThigh:  return m.leftThighCm
        case .rightThigh: return m.rightThighCm
        case .neck:       return m.neckCm
        case .shoulders:  return m.shouldersCm
        }
    }
}

private struct MeasurementsTab: View {
    @Environment(AppState.self) private var appState
    @State private var showAddMeasurement = false
    @State private var selectedMetric: MeasurementMetric = .waist

    private var measurements: [BodyMeasurement] {
        appState.bodyMeasurements.sorted { $0.date > $1.date }
    }

    private var chartData: [(date: Date, value: Double)] {
        appState.bodyMeasurements
            .sorted { $0.date < $1.date }
            .compactMap { m in
                guard let v = selectedMetric.value(from: m) else { return nil }
                return (m.date, v)
            }
    }

    var body: some View {
        List {
            if let latest = measurements.first {
                Section("Latest Measurements") {
                    MeasurementRow(label: "Chest",        value: latest.chestCm,      unit: "cm")
                    MeasurementRow(label: "Waist",        value: latest.waistCm,      unit: "cm")
                    MeasurementRow(label: "Hips",         value: latest.hipsCm,       unit: "cm")
                    MeasurementRow(label: "Left Arm",     value: latest.leftArmCm,    unit: "cm")
                    MeasurementRow(label: "Right Arm",    value: latest.rightArmCm,   unit: "cm")
                    MeasurementRow(label: "Left Thigh",   value: latest.leftThighCm,  unit: "cm")
                    MeasurementRow(label: "Right Thigh",  value: latest.rightThighCm, unit: "cm")
                    MeasurementRow(label: "Neck",         value: latest.neckCm,       unit: "cm")
                    MeasurementRow(label: "Shoulders",    value: latest.shouldersCm,  unit: "cm")
                }
            }

            Section {
                Button {
                    showAddMeasurement = true
                } label: {
                    Label("Log Measurements", systemImage: "ruler")
                        .foregroundColor(AppTheme.primary)
                }
            }

            if measurements.count > 1 {
                Section("Trend") {
                    Picker("Metric", selection: $selectedMetric) {
                        ForEach(MeasurementMetric.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)

                    if chartData.count > 1 {
                        Chart {
                            ForEach(Array(chartData.enumerated()), id: \.offset) { _, point in
                                LineMark(x: .value("Date", point.date), y: .value(selectedMetric.rawValue, point.value))
                                    .foregroundStyle(AppTheme.primary)
                                    .interpolationMethod(.catmullRom)
                                PointMark(x: .value("Date", point.date), y: .value(selectedMetric.rawValue, point.value))
                                    .foregroundStyle(AppTheme.primary)
                            }
                        }
                        .frame(height: 180)
                    } else {
                        Text("Not enough \(selectedMetric.rawValue.lowercased()) entries yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if measurements.count > 1 {
                Section("History") {
                    ForEach(measurements) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline.bold())
                            HStack(spacing: 12) {
                                if let v = m.waistCm   { Text("Waist \(v.formatted1)").font(.caption).foregroundColor(.secondary) }
                                if let v = m.chestCm   { Text("Chest \(v.formatted1)").font(.caption).foregroundColor(.secondary) }
                                if let v = m.hipsCm    { Text("Hips \(v.formatted1)").font(.caption).foregroundColor(.secondary) }
                            }
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                appState.deleteBodyMeasurement(id: m.id)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showAddMeasurement) {
            AddMeasurementSheet()
        }
    }
}

private struct MeasurementRow: View {
    let label: String
    let value: Double?
    let unit: String
    var body: some View {
        if let v = value {
            HStack {
                Text(label).foregroundColor(.secondary)
                Spacer()
                Text("\(v.formatted1) \(unit)").font(.subheadline)
            }
        }
    }
}

// MARK: - Add Measurement Sheet

private struct AddMeasurementSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var chest = ""
    @State private var waist = ""
    @State private var hips = ""
    @State private var leftArm = ""
    @State private var rightArm = ""
    @State private var leftThigh = ""
    @State private var rightThigh = ""
    @State private var neck = ""
    @State private var shoulders = ""
    @State private var notes = ""

    private var allFields: [String] {
        [chest, waist, hips, leftArm, rightArm, leftThigh, rightThigh, neck, shoulders]
    }

    /// A circumference in centimetres, or nil if it isn't one.
    private func measurement(_ text: String) -> Double? {
        BodyMetricLimits.parse(text, in: BodyMetricLimits.measurementCm)
    }

    private var hasAnyValidMeasurement: Bool {
        allFields.contains { measurement($0) != nil }
    }

    /// True when something has been typed that isn't a usable measurement, so
    /// the form can say why Save is still off.
    private var hasInvalidEntry: Bool {
        allFields.contains { !$0.isEmpty && measurement($0) == nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Circumference (cm)") {
                    MeasInput(label: "Chest",       text: $chest)
                    MeasInput(label: "Waist",       text: $waist)
                    MeasInput(label: "Hips",        text: $hips)
                    MeasInput(label: "Left Arm",    text: $leftArm)
                    MeasInput(label: "Right Arm",   text: $rightArm)
                    MeasInput(label: "Left Thigh",  text: $leftThigh)
                    MeasInput(label: "Right Thigh", text: $rightThigh)
                    MeasInput(label: "Neck",        text: $neck)
                    MeasInput(label: "Shoulders",   text: $shoulders)
                    if hasInvalidEntry {
                        Text(BodyMetricLimits.rangeHint(BodyMetricLimits.measurementCm, unit: "cm"))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Log Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel")
                        .accessibilityHint("Discards these measurements")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let m = BodyMeasurement(
                            chestCm:       measurement(chest),
                            waistCm:       measurement(waist),
                            hipsCm:        measurement(hips),
                            leftArmCm:     measurement(leftArm),
                            rightArmCm:    measurement(rightArm),
                            leftThighCm:   measurement(leftThigh),
                            rightThighCm:  measurement(rightThigh),
                            neckCm:        measurement(neck),
                            shouldersCm:   measurement(shoulders),
                            notes: notes
                        )
                        appState.addBodyMeasurement(m)
                        HapticManager.success()
                        dismiss()
                    }
                    // Enabled only when at least one field holds a *valid*
                    // measurement. It used to be enabled by any non-empty text,
                    // so "-30" and "0" both saved: `Double(text)` accepts them
                    // and nothing checked the sign.
                    .disabled(!hasAnyValidMeasurement)
                    .accessibilityLabel("Save")
                    .accessibilityHint(hasAnyValidMeasurement
                        ? "Saves these measurements"
                        : "Enter at least one measurement in centimetres first")
                }
            }
        }
    }
}

private struct MeasInput: View {
    let label: String
    @Binding var text: String
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("cm", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .accessibilityLabel("\(label) in centimetres")
        }
    }
}
