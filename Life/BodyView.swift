import SwiftUI
import Charts

// MARK: - Body View

struct BodyView: View {

    @Environment(AppState.self) private var appState
    @State private var selectedTab: BodyTab = .weight

    enum BodyTab: String, CaseIterable, Identifiable {
        case weight = "Weight"
        case composition = "Comp"
        case vitals = "Vitals"
        case measurements = "Measures"
        case lifts = "Lifts"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented picker
            Picker("Tab", selection: $selectedTab) {
                ForEach(BodyTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // Content
            switch selectedTab {
            case .weight:       WeightTab()
            case .composition:  CompositionTab()
            case .vitals:       VitalsTab()
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
    @FocusState private var isWeightFocused: Bool
    @State private var chartRange: ChartRange = .month
    @State private var goalInput = ""
    @FocusState private var isGoalFocused: Bool

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
                            Text(current.formatted1)
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
                                    Text("Goal: \(goal.formatted1) \(unit.label)")
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
                HStack {
                    TextField("e.g. 75.5", text: $weightInput)
                        .keyboardType(.decimalPad)
                        .focused($isWeightFocused)
                    Text(unit.label)
                        .foregroundColor(.secondary)
                    Button("Add") {
                        let normalized = weightInput.replacingOccurrences(of: ",", with: ".")
                        guard let value = Double(normalized) else { return }
                        let valueKg = unit == .kg ? value : WeightUnit.lbs.convert(value, to: .kg)
                        appState.logBodyWeight(valueKg: valueKg)
                        weightInput = ""
                        isWeightFocused = false
                    }
                    .disabled(Double(weightInput.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }

            // Goal weight
            Section("Goal Weight") {
                HStack {
                    TextField(goalWeightDisplay != nil ? goalWeightDisplay!.formatted1 : "None set", text: $goalInput)
                        .keyboardType(.decimalPad)
                        .focused($isGoalFocused)
                    Text(unit.label)
                        .foregroundColor(.secondary)
                    Button("Save") {
                        let normalized = goalInput.replacingOccurrences(of: ",", with: ".")
                        guard let value = Double(normalized) else { return }
                        appState.setGoalWeight(kg: unit.convert(value, to: .kg))
                        goalInput = ""
                        isGoalFocused = false
                    }
                    .disabled(Double(goalInput.replacingOccurrences(of: ",", with: ".")) == nil)
                }
                if goalWeightDisplay != nil {
                    Button("Clear Goal", role: .destructive) {
                        appState.setGoalWeight(kg: nil)
                    }
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
                            Text("\(displayValue.formatted1) \(unit.label)")
                                .font(.subheadline)
                        }
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
    @State private var isImporting = false
    @State private var importError: String? = nil
    @State private var selectedMetric: CompMetric = .bodyFat
    @State private var showAddEntry = false

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
                        InfoRow(label: "Body Fat", value: String(format: "%.1f%%", bf * 100))
                    }
                    if let lm = latest.leanMassKg {
                        InfoRow(label: "Lean Mass", value: "\(lm.formatted1) kg")
                    }
                    if let bmi = latest.bmi {
                        InfoRow(label: "BMI", value: bmi.formatted1)
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
                        Label("Import from Apple Health", systemImage: "heart.fill")
                            .foregroundColor(.red)
                        Spacer()
                        if isImporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isImporting)

                if let err = importError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button {
                    showAddEntry = true
                } label: {
                    Label("Log Manually", systemImage: "pencil")
                        .foregroundColor(AppTheme.primary)
                }
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
                                    Text("LM: \(lm.formatted1) kg")
                                        .font(.caption)
                                }
                                if let bmi = entry.bmi {
                                    Text("BMI: \(bmi.formatted1)")
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

    private func importFromHealthKit() {
        isImporting = true
        importError = nil
        Task {
            let granted = await healthKitManager.requestPermissions()
            guard granted else {
                await MainActor.run {
                    isImporting = false
                    importError = "HealthKit access denied. Please allow in Settings > Health > Data Access."
                }
                return
            }

            let data = await healthKitManager.importBodyData(daysBack: 365)

            var entryMap: [String: BodyCompEntry] = [:]

            // Weight goes to WeightEntry
            for (date, kg) in data.weight {
                await MainActor.run {
                    appState.logBodyWeight(valueKg: kg, date: date)
                }
            }

            for (date, pct) in data.bodyFat {
                let key = date.dayKey
                var entry = entryMap[key] ?? BodyCompEntry(date: date)
                entry.bodyFatPct = pct
                entryMap[key] = entry
            }

            for (date, kg) in data.leanMass {
                let key = date.dayKey
                var entry = entryMap[key] ?? BodyCompEntry(date: date)
                entry.leanMassKg = kg
                entryMap[key] = entry
            }

            for (date, val) in data.bmi {
                let key = date.dayKey
                var entry = entryMap[key] ?? BodyCompEntry(date: date)
                entry.bmi = val
                entryMap[key] = entry
            }

            let newEntries = entryMap.values.filter {
                $0.bodyFatPct != nil || $0.leanMassKg != nil || $0.bmi != nil
            }
            await MainActor.run {
                appState.mergeBodyCompEntries(Array(newEntries))
                isImporting = false
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

    private var bodyFatPct: Double? {
        guard let v = Double(bodyFatText) else { return nil }
        return v / 100
    }
    private var bmi: Double? { Double(bmiText) }

    private var canSave: Bool { bodyFatPct != nil || bmi != nil }

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
                        Text("%").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("BMI")
                        Spacer()
                        TextField("0", text: $bmiText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
            }
            .navigationTitle("Log Body Composition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var entry = BodyCompEntry(date: date)
                        entry.bodyFatPct = bodyFatPct
                        entry.bmi = bmi
                        entry.source = "manual"
                        appState.mergeBodyCompEntries([entry])
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

// MARK: - Vitals Tab

/// The metrics Life reads out of Apple Health that aren't body composition —
/// sleep and the recovery signals a wrist tracker records overnight.
private enum VitalMetric: String, CaseIterable, Identifiable {
    case sleep = "Sleep"
    case restingHr = "Resting HR"
    case hrv = "HRV"
    case spo2 = "SpO₂"
    case breathing = "Breathing"
    case energy = "Energy"
    case vo2Max = "VO₂ Max"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .sleep:     return "h"
        case .restingHr: return "bpm"
        case .hrv:       return "ms"
        case .spo2:      return "%"
        case .breathing: return "br/min"
        case .energy:    return "kcal"
        case .vo2Max:    return "ml/kg·min"
        }
    }

    var colour: Color {
        switch self {
        case .sleep:     return .indigo
        case .restingHr: return .pink
        case .hrv:       return AppTheme.primary
        case .spo2:      return .cyan
        case .breathing: return .teal
        case .energy:    return .orange
        case .vo2Max:    return .green
        }
    }

    var icon: String {
        switch self {
        case .sleep:     return "bed.double.fill"
        case .restingHr: return "heart.fill"
        case .hrv:       return "waveform.path.ecg"
        case .spo2:      return "drop.fill"
        case .breathing: return "lungs.fill"
        case .energy:    return "flame.fill"
        case .vo2Max:    return "figure.run"
        }
    }

    /// Pulls this metric out of a day's record, in the unit shown above.
    /// Sleep is converted from stored minutes to hours for charting.
    func value(from day: HealthDay) -> Double? {
        switch self {
        case .sleep:     return day.sleepMin.map { Double($0) / 60 }
        case .restingHr: return day.restingHr
        case .hrv:       return day.hrvMs
        case .spo2:      return day.spo2Pct
        case .breathing: return day.respiratoryRate
        case .energy:    return day.activeEnergyKcal
        case .vo2Max:    return day.vo2Max
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .sleep:
            let total = Int((value * 60).rounded())
            return "\(total / 60)h \(total % 60)m"
        case .restingHr, .energy:
            return String(format: "%.0f", value)
        case .spo2, .breathing, .vo2Max:
            return String(format: "%.1f", value)
        case .hrv:
            return String(format: "%.0f", value)
        }
    }

    /// Charts for these metrics shouldn't start at zero — a resting heart rate
    /// axis running from 0 flattens the variation that matters.
    var zeroBaseline: Bool {
        switch self {
        case .energy, .sleep: return true
        default:              return false
        }
    }
}

/// One slice of a night's sleep, for the stacked stage bar.
private struct SleepStageSlice: Identifiable {
    let id: String
    let minutes: Int
    let colour: Color
    var label: String { id }
    var formatted: String { "\(minutes / 60)h \(minutes % 60)m" }
}

private struct VitalsTab: View {

    @Environment(AppState.self) private var appState
    @State private var selectedMetric: VitalMetric = .sleep
    @State private var chartRange: VitalsRange = .month
    @State private var isImporting = false
    @State private var importError: String? = nil
    @State private var healthKitManager = HealthKitManager()

    enum VitalsRange: String, CaseIterable {
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

    private var history: [HealthDay] { appState.healthHistory }

    private var rangeDays: [HealthDay] {
        guard let days = chartRange.days else { return history }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return history
        }
        let cutoffKey = cutoff.dayKey
        return history.filter { $0.dayKey >= cutoffKey }
    }

    private var chartData: [(date: Date, value: Double)] {
        rangeDays.compactMap { day in
            guard let value = selectedMetric.value(from: day),
                  let date = _dayKeyFormatter.date(from: day.dayKey) else { return nil }
            return (date, value)
        }
    }

    /// Most recent reading for the selected metric, however long ago.
    private var latest: (day: HealthDay, value: Double)? {
        for day in history.reversed() {
            if let value = selectedMetric.value(from: day) { return (day, value) }
        }
        return nil
    }

    private var average: Double? {
        let values = chartData.map(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var lastNight: HealthDay? { appState.lastNightSleep }

    var body: some View {
        List {
            latestSection
            if selectedMetric == .sleep, let night = lastNight { sleepStageSection(night) }
            metricPickerSection
            chartSection
            importSection
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Sections

    @ViewBuilder
    private var latestSection: some View {
        Section {
            if let latest = latest {
                VStack(alignment: .leading, spacing: 4) {
                    Label(selectedMetric.rawValue, systemImage: selectedMetric.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(selectedMetric.format(latest.value))
                            .font(.largeTitle.bold())
                        if selectedMetric != .sleep {
                            Text(selectedMetric.unit)
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                    if let average = average, chartData.count > 1 {
                        Text("\(chartRange.rawValue) average \(selectedMetric.format(average))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let date = _dayKeyFormatter.date(from: latest.day.dayKey), !date.isToday {
                        Text("Last reading \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No \(selectedMetric.rawValue.lowercased()) data yet")
                        .font(.subheadline)
                    Text("Import from Apple Health below. If nothing appears, check your tracker is writing this metric into the Health app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func sleepStageSection(_ night: HealthDay) -> some View {
        let stages: [SleepStageSlice] = [
            SleepStageSlice(id: "Deep",  minutes: night.deepMin ?? 0,  colour: .indigo),
            SleepStageSlice(id: "REM",   minutes: night.remMin ?? 0,   colour: .purple),
            SleepStageSlice(id: "Light", minutes: night.lightMin ?? 0, colour: .blue.opacity(0.6)),
            SleepStageSlice(id: "Awake", minutes: night.awakeMin ?? 0, colour: .orange.opacity(0.7))
        ].filter { $0.minutes > 0 }

        Section {
            if stages.isEmpty {
                Text("Your tracker reported a total but no stage breakdown for this night.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Chart(stages) { stage in
                    BarMark(
                        x: .value("Minutes", stage.minutes),
                        y: .value("Night", "stages")
                    )
                    .foregroundStyle(stage.colour)
                    .annotation(position: .overlay) {
                        if stage.minutes >= 45 {
                            Text(stage.label)
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(height: 44)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)

                ForEach(stages) { stage in
                    HStack {
                        Circle().fill(stage.colour).frame(width: 8, height: 8)
                        Text(stage.label)
                        Spacer()
                        Text(stage.formatted)
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                }
            }

            if let efficiency = night.sleepEfficiency {
                InfoRow(label: "Efficiency", value: String(format: "%.0f%%", efficiency * 100))
            }
            if let bedtime = night.bedtime, let wake = night.wakeTime {
                InfoRow(
                    label: "Asleep",
                    value: "\(bedtime.formatted(date: .omitted, time: .shortened)) – \(wake.formatted(date: .omitted, time: .shortened))"
                )
            }
        } header: {
            Text("Last Night")
        }
    }

    @ViewBuilder
    private var metricPickerSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VitalMetric.allCases) { metric in
                        let isSelected = metric == selectedMetric
                        Button {
                            selectedMetric = metric
                        } label: {
                            Text(metric.rawValue)
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.chipRadius)
                                        .fill(isSelected ? metric.colour.opacity(0.18) : Color(.tertiarySystemFill))
                                )
                                .foregroundColor(isSelected ? metric.colour : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        if chartData.count > 1 {
            Section {
                Picker("Range", selection: $chartRange) {
                    ForEach(VitalsRange.allCases, id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                Chart {
                    ForEach(Array(chartData.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value(selectedMetric.rawValue, point.value)
                        )
                        .foregroundStyle(selectedMetric.colour)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value(selectedMetric.rawValue, point.value)
                        )
                        .foregroundStyle(selectedMetric.colour.opacity(0.12))
                        .interpolationMethod(.catmullRom)
                    }
                    if selectedMetric == .sleep {
                        RuleMark(y: .value("Goal", Double(appState.healthSettings.sleepGoalMinutes) / 60))
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                }
                .frame(height: 190)
                .chartYScale(domain: .automatic(includesZero: selectedMetric.zeroBaseline))
            } header: {
                Text("Trend")
            }
        }
    }

    @ViewBuilder
    private var importSection: some View {
        Section {
            Button {
                importFromHealthKit()
            } label: {
                HStack {
                    Label(
                        appState.healthSettings.hasBackfilled ? "Sync from Apple Health" : "Import from Apple Health",
                        systemImage: "heart.fill"
                    )
                    .foregroundColor(.red)
                    Spacer()
                    if isImporting { ProgressView() }
                }
            }
            .disabled(isImporting)

            if let importError = importError {
                Text(importError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        } footer: {
            Text("Pulls a year of sleep, heart and activity history. Anything your tracker writes into Apple Health shows up here.")
        }
    }

    // MARK: Import

    private func importFromHealthKit() {
        isImporting = true
        importError = nil
        Task {
            let granted = await healthKitManager.requestPermissions()
            guard granted else {
                await MainActor.run {
                    isImporting = false
                    importError = "HealthKit access denied. Please allow in Settings > Health > Data Access."
                }
                return
            }

            let days = await healthKitManager.fetchDailyMetrics(daysBack: 365)
            let steps = await healthKitManager.fetchDailySteps(daysBack: 365)

            await MainActor.run {
                appState.mergeHealthDays(Array(days.values))
                appState.mergeSteps(steps)
                appState.setHealthSettings { $0.hasBackfilled = true }
                isImporting = false
                if days.isEmpty {
                    importError = "Apple Health returned no sleep or heart data. Check Settings > Health > Data Access > Life, and that your tracker is syncing into Health."
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
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Log Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let m = BodyMeasurement(
                            chestCm:       Double(chest),
                            waistCm:       Double(waist),
                            hipsCm:        Double(hips),
                            leftArmCm:     Double(leftArm),
                            rightArmCm:    Double(rightArm),
                            leftThighCm:   Double(leftThigh),
                            rightThighCm:  Double(rightThigh),
                            neckCm:        Double(neck),
                            shouldersCm:   Double(shoulders),
                            notes: notes
                        )
                        appState.addBodyMeasurement(m)
                        HapticManager.success()
                        dismiss()
                    }
                    .disabled([chest, waist, hips, leftArm, rightArm, leftThigh, rightThigh, neck, shoulders].allSatisfy { $0.isEmpty })
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
        }
    }
}
