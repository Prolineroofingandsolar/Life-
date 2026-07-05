import SwiftUI

// MARK: - Calculator Tab

private enum CalcTab: String, CaseIterable {
    case oneRM = "1RM"
    case plate = "Plate"
    case bmi = "BMI"
    case macros = "Macros"
}

// MARK: - CalculatorsView

struct CalculatorsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: CalcTab = .oneRM

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("Calculator", selection: $selectedTab) {
                    ForEach(CalcTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: selectedTab) { _, _ in HapticManager.selection() }

                switch selectedTab {
                case .oneRM:
                    OneRMCalculatorView(unit: appState.workoutSettings.weightUnit)
                case .plate:
                    PlateCalculatorView(unit: appState.workoutSettings.weightUnit)
                case .bmi:
                    BMICalculatorView(unit: appState.workoutSettings.weightUnit)
                case .macros:
                    MacroCalculatorView(unit: appState.workoutSettings.weightUnit)
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Calculators")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Card Modifier

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(AppTheme.cardBg)
            .cornerRadius(AppTheme.cardRadius)
            .padding(.horizontal)
    }
}

private extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

// MARK: - 1RM Calculator

private struct OneRMCalculatorView: View {
    let unit: WeightUnit

    @State private var weightText: String = ""
    @State private var reps: Int = 5
    @State private var selectedUnit: WeightUnit

    init(unit: WeightUnit) {
        self.unit = unit
        _selectedUnit = State(initialValue: unit)
    }

    private let percentages: [Double] = [50, 60, 70, 75, 80, 85, 90, 95]

    private var weight: Double { Double(weightText) ?? 0 }

    private var oneRM: Double {
        guard weight > 0, reps >= 1 else { return 0 }
        return weight * (1 + Double(reps) / 30)
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Inputs")
                    .font(.headline)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weight")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Unit", selection: $selectedUnit) {
                            ForEach(WeightUnit.allCases) { u in
                                Text(u.label).tag(u)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Stepper("\(reps) reps", value: $reps, in: 1...20)
                            .onChange(of: reps) { _, _ in HapticManager.selection() }
                    }
                }
            }
            .cardStyle()

            if oneRM > 0 {
                VStack(spacing: 6) {
                    Text("Estimated 1RM")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(oneRM.formatted1) \(selectedUnit.label)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.primary)
                }
                .frame(maxWidth: .infinity)
                .cardStyle()

                VStack(alignment: .leading, spacing: 0) {
                    Text("Training Percentages")
                        .font(.headline)
                        .padding(.bottom, 10)

                    VStack(spacing: 0) {
                        ForEach(percentages, id: \.self) { pct in
                            let calc = oneRM * (pct / 100)
                            HStack {
                                Text("\(Int(pct))%")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 44, alignment: .leading)
                                Spacer()
                                Text("\(calc.formatted1) \(selectedUnit.label)")
                                    .font(.subheadline.bold())
                            }
                            .padding(.vertical, 8)
                            if pct != percentages.last {
                                Divider()
                            }
                        }
                    }
                }
                .cardStyle()
            }
        }
    }
}

// MARK: - Plate Calculator

private struct PlateCalculatorView: View {
    let unit: WeightUnit

    @State private var targetText: String = ""
    @State private var barText: String = "20"
    @State private var selectedUnit: WeightUnit

    init(unit: WeightUnit) {
        self.unit = unit
        _selectedUnit = State(initialValue: unit)
    }

    private let plateSizesKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    private let plateSizesLbs: [Double] = [45, 35, 25, 10, 5, 2.5]

    private var plateSizes: [Double] {
        selectedUnit == .kg ? plateSizesKg : plateSizesLbs
    }

    private var target: Double { Double(targetText) ?? 0 }
    private var barWeight: Double { Double(barText) ?? 0 }

    private struct PlateCount: Identifiable {
        let id = UUID()
        let size: Double
        let count: Int
    }

    private var platesPerSide: [PlateCount] {
        guard target > barWeight else { return [] }
        var remaining = (target - barWeight) / 2
        var result: [PlateCount] = []
        for size in plateSizes {
            if remaining <= 0 { break }
            let count = Int(remaining / size)
            if count > 0 {
                result.append(PlateCount(size: size, count: count))
                remaining -= Double(count) * size
            }
        }
        return result
    }

    private var totalLoaded: Double {
        guard target > barWeight else { return barWeight }
        let platesWeight = platesPerSide.reduce(0.0) { $0 + $1.size * Double($1.count) } * 2
        return barWeight + platesWeight
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Inputs")
                    .font(.headline)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target Weight")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("0", text: $targetText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bar Weight")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("20", text: $barText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Unit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Unit", selection: $selectedUnit) {
                        ForEach(WeightUnit.allCases) { u in
                            Text(u.label).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedUnit) { _, _ in HapticManager.selection() }
                }
            }
            .cardStyle()

            if target > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Each Side")
                            .font(.headline)
                        Spacer()
                        Text("Total: \(totalLoaded.formatted1) \(selectedUnit.label)")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.primary)
                            .fontWeight(.semibold)
                    }

                    if platesPerSide.isEmpty {
                        Text(target <= barWeight ? "Target ≤ bar weight" : "No plates needed")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(platesPerSide) { plate in
                                PlateChip(size: plate.size, count: plate.count, unit: selectedUnit)
                            }
                        }
                    }
                }
                .cardStyle()
            }
        }
    }
}

private struct PlateChip: View {
    let size: Double
    let count: Int
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: 4) {
            Text("\(size.formatted1)\(unit.label)")
                .fontWeight(.semibold)
            Text("× \(count)")
                .foregroundColor(.secondary)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppTheme.primary.opacity(0.15))
        .foregroundColor(AppTheme.primary)
        .cornerRadius(20)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - BMI Calculator

private enum HeightInputMode: String, CaseIterable {
    case cm = "cm"
    case ftIn = "ft/in"
}

private struct BMICalculatorView: View {
    let unit: WeightUnit

    @State private var weightText: String = ""
    @State private var selectedUnit: WeightUnit
    @State private var heightCmText: String = ""
    @State private var heightFtText: String = ""
    @State private var heightInText: String = ""
    @State private var heightMode: HeightInputMode = .cm

    init(unit: WeightUnit) {
        self.unit = unit
        _selectedUnit = State(initialValue: unit)
    }

    private var weightKg: Double {
        let w = Double(weightText) ?? 0
        return selectedUnit == .kg ? w : w / 2.20462
    }

    private var heightM: Double {
        switch heightMode {
        case .cm:
            return (Double(heightCmText) ?? 0) / 100
        case .ftIn:
            let ft = Double(heightFtText) ?? 0
            let inches = Double(heightInText) ?? 0
            return (ft * 12 + inches) * 0.0254
        }
    }

    private var bmi: Double {
        guard weightKg > 0, heightM > 0 else { return 0 }
        return weightKg / (heightM * heightM)
    }

    private var bmiCategory: (label: String, color: Color) {
        switch bmi {
        case ..<18.5:  return ("Underweight", .blue)
        case ..<25:    return ("Normal", AppTheme.primary)
        case ..<30:    return ("Overweight", .orange)
        default:       return ("Obese", .red)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Inputs")
                    .font(.headline)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weight")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Unit", selection: $selectedUnit) {
                            ForEach(WeightUnit.allCases) { u in
                                Text(u.label).tag(u)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                        .onChange(of: selectedUnit) { _, _ in HapticManager.selection() }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Height")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Height Mode", selection: $heightMode) {
                        ForEach(HeightInputMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: heightMode) { _, _ in HapticManager.selection() }
                }

                if heightMode == .cm {
                    HStack {
                        TextField("Height (cm)", text: $heightCmText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Text("cm")
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        TextField("ft", text: $heightFtText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        Text("ft")
                            .foregroundColor(.secondary)
                        TextField("in", text: $heightInText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        Text("in")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .cardStyle()

            if bmi > 0 {
                VStack(spacing: 10) {
                    Text("BMI")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(bmi.formatted1)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.primary)

                    Text(bmiCategory.label)
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(bmiCategory.color.opacity(0.18))
                        .foregroundColor(bmiCategory.color)
                        .cornerRadius(20)
                }
                .frame(maxWidth: .infinity)
                .cardStyle()

                VStack(alignment: .leading, spacing: 0) {
                    Text("Categories")
                        .font(.headline)
                        .padding(.bottom, 10)

                    let categories: [(String, String, Color)] = [
                        ("Underweight", "< 18.5", .blue),
                        ("Normal", "18.5 – 24.9", AppTheme.primary),
                        ("Overweight", "25 – 29.9", .orange),
                        ("Obese", "≥ 30", .red)
                    ]

                    VStack(spacing: 0) {
                        ForEach(categories, id: \.0) { name, range, color in
                            HStack {
                                Circle()
                                    .fill(color)
                                    .frame(width: 8, height: 8)
                                Text(name)
                                    .font(.subheadline)
                                Spacer()
                                Text(range)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                            if name != "Obese" {
                                Divider()
                            }
                        }
                    }
                }
                .cardStyle()
            }
        }
    }
}

// MARK: - Macro / Calorie Calculator

private enum ActivityLevel: String, CaseIterable, Identifiable {
    case sedentary = "Sedentary"
    case light = "Light"
    case moderate = "Moderate"
    case active = "Active"
    case veryActive = "Very Active"
    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .sedentary:  return 1.2
        case .light:      return 1.375
        case .moderate:   return 1.55
        case .active:     return 1.725
        case .veryActive: return 1.9
        }
    }

    var subtitle: String {
        switch self {
        case .sedentary:  return "Little to no exercise"
        case .light:      return "1–3 workouts/week"
        case .moderate:   return "3–5 workouts/week"
        case .active:     return "6–7 workouts/week"
        case .veryActive: return "Physical job or 2x/day training"
        }
    }
}

private enum MacroGoal: String, CaseIterable, Identifiable {
    case lose = "Lose"
    case maintain = "Maintain"
    case gain = "Gain"
    var id: String { rawValue }

    /// Calorie adjustment applied to TDEE.
    var calorieDelta: Double {
        switch self {
        case .lose:     return -500
        case .maintain: return 0
        case .gain:     return 300
        }
    }
}

private struct MacroCalculatorView: View {
    let unit: WeightUnit

    @State private var weightText: String = ""
    @State private var selectedUnit: WeightUnit
    @State private var ageText: String = "30"
    @State private var isMale: Bool = true
    @State private var heightCmText: String = ""
    @State private var heightFtText: String = ""
    @State private var heightInText: String = ""
    @State private var heightMode: HeightInputMode = .cm
    @State private var activityLevel: ActivityLevel = .moderate
    @State private var goal: MacroGoal = .maintain

    init(unit: WeightUnit) {
        self.unit = unit
        _selectedUnit = State(initialValue: unit)
    }

    private var weightKg: Double {
        let w = Double(weightText) ?? 0
        return selectedUnit == .kg ? w : w / 2.20462
    }

    private var heightCm: Double {
        switch heightMode {
        case .cm:
            return Double(heightCmText) ?? 0
        case .ftIn:
            let ft = Double(heightFtText) ?? 0
            let inches = Double(heightInText) ?? 0
            return (ft * 12 + inches) * 2.54
        }
    }

    private var age: Int { Int(ageText) ?? 0 }

    /// Mifflin-St Jeor basal metabolic rate.
    private var bmr: Double {
        guard weightKg > 0, heightCm > 0, age > 0 else { return 0 }
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return isMale ? base + 5 : base - 161
    }

    private var tdee: Double { bmr * activityLevel.multiplier }
    private var targetCalories: Double { max(0, tdee + goal.calorieDelta) }

    /// 1.8g protein/kg bodyweight, 25% of calories from fat, remainder carbs.
    private var proteinGrams: Double { weightKg * 1.8 }
    private var fatGrams: Double { targetCalories * 0.25 / 9 }
    private var carbGrams: Double {
        max(0, (targetCalories - proteinGrams * 4 - fatGrams * 9) / 4)
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Inputs")
                    .font(.headline)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weight")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Unit", selection: $selectedUnit) {
                            ForEach(WeightUnit.allCases) { u in
                                Text(u.label).tag(u)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Age")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("30", text: $ageText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sex")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Sex", selection: $isMale) {
                            Text("Male").tag(true)
                            Text("Female").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: isMale) { _, _ in HapticManager.selection() }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Height")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Height Mode", selection: $heightMode) {
                        ForEach(HeightInputMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: heightMode) { _, _ in HapticManager.selection() }
                }

                if heightMode == .cm {
                    HStack {
                        TextField("Height (cm)", text: $heightCmText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Text("cm")
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        TextField("ft", text: $heightFtText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        Text("ft")
                            .foregroundColor(.secondary)
                        TextField("in", text: $heightInText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        Text("in")
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Activity Level")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Activity Level", selection: $activityLevel) {
                        ForEach(ActivityLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: activityLevel) { _, _ in HapticManager.selection() }
                    Text(activityLevel.subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Goal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Goal", selection: $goal) {
                        ForEach(MacroGoal.allCases) { g in
                            Text(g.rawValue).tag(g)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: goal) { _, _ in HapticManager.selection() }
                }
            }
            .cardStyle()

            if targetCalories > 0 {
                VStack(spacing: 6) {
                    Text("Daily Calories")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(Int(targetCalories))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.primary)
                    Text("Maintenance (TDEE): \(Int(tdee)) kcal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .cardStyle()

                VStack(alignment: .leading, spacing: 0) {
                    Text("Macros")
                        .font(.headline)
                        .padding(.bottom, 10)

                    HStack(spacing: 8) {
                        MacroStatCell(label: "Protein", grams: proteinGrams, color: AppTheme.primary)
                        MacroStatCell(label: "Carbs", grams: carbGrams, color: .orange)
                        MacroStatCell(label: "Fat", grams: fatGrams, color: .blue)
                    }
                }
                .cardStyle()
            }
        }
    }
}

private struct MacroStatCell: View {
    let label: String
    let grams: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(Int(grams))g")
                .font(.headline.bold())
                .foregroundColor(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.12))
        .cornerRadius(10)
    }
}
