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
        let cutoff: Date? = chartRange.days.map { Calendar.current.date(byAdding: .day, value: -$0, to: Date())! }
        return entries.compactMap { entry in
            if let cutoff, entry.date < cutoff { return nil }
            let val = unit == .kg ? entry.valueKg : WeightUnit.kg.convert(entry.valueKg, to: .lbs)
            return (entry.date, val)
        }
    }

    private var currentWeight: Double? {
        entries.map { unit == .kg ? $0.valueKg : WeightUnit.kg.convert($0.valueKg, to: .lbs) }.last
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
                            .foregroundStyle(Color(hex: "#30d158"))
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Date", entry.date),
                                y: .value("Weight", entry.value)
                            )
                            .foregroundStyle(Color(hex: "#30d158").opacity(0.1))
                            .interpolationMethod(.catmullRom)
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
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
                    VStack(spacing: 12) {
                        Image(systemName: "dumbbell")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No lift records yet")
                            .font(.headline)
                        Text("Complete workouts to see your PRs here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
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
    let item: LiftPRItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.exercise.name)
                    .font(.subheadline)
                Text("\(item.pr.bestWeight.formatted1) kg × \(item.pr.bestReps)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("e1RM")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(item.pr.best1RM.formatted1) kg")
                    .font(.subheadline.bold())
                    .foregroundColor(Color(hex: "#30d158"))
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Measurements Tab (P3.2)

private struct MeasurementsTab: View {
    @Environment(AppState.self) private var appState
    @State private var showAddMeasurement = false

    private var measurements: [BodyMeasurement] {
        appState.bodyMeasurements.sorted { $0.date > $1.date }
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
                        .foregroundColor(Color(hex: "#30d158"))
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
