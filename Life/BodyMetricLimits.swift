import Foundation

// MARK: - Body Metric Limits

/// Accepted ranges for every hand-entered body metric, and the parsing that
/// enforces them.
///
/// Every one of these fields used to accept whatever `Double(text)` returned.
/// That let through a body weight of 0, a goal weight of 0, 150% body fat, a
/// negative BMI and negative circumferences — each of which then propagated
/// into charts, averages and the goal-progress bar, where a single zero drags a
/// trend line to the floor and can't be told apart from a real reading.
///
/// The ranges are deliberately generous. They exist to catch a mistyped or
/// impossible value, not to tell anyone what their body should measure: the
/// weight range spans well beyond both the lightest and heaviest recorded adult
/// weights, and body fat covers the full 0–100% the unit allows.
enum BodyMetricLimits {

    /// Body weight in kilograms.
    static let weightKg: ClosedRange<Double> = 1...500

    /// Goal weight uses the same range as an ordinary weight record — a goal is
    /// a weight, and there is no reason for it to accept a value a reading
    /// wouldn't.
    static let goalWeightKg: ClosedRange<Double> = weightKg

    /// Body fat as a percentage, as typed. Stored as a 0–1 fraction.
    static let bodyFatPercent: ClosedRange<Double> = 1...100

    /// BMI. The extremes here are far outside anything clinically plausible;
    /// the point is to reject negatives and typos, not to judge.
    static let bmi: ClosedRange<Double> = 5...200

    /// Lean mass in kilograms.
    static let leanMassKg: ClosedRange<Double> = 1...300

    /// Any body circumference in centimetres.
    static let measurementCm: ClosedRange<Double> = 1...300

    // MARK: Parsing

    /// Parses a typed number, accepting a comma as the decimal separator, and
    /// returns it only when it's finite and inside `range`.
    ///
    /// Returning nil for a rejected value is what lets the callers keep their
    /// existing shape: an Add or Save button is disabled exactly when this
    /// returns nil, so an out-of-range number can't be committed and doesn't
    /// need a separate error path.
    static func parse(_ text: String, in range: ClosedRange<Double>) -> Double? {
        let trimmed = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty, let value = Double(trimmed) else { return nil }
        return validate(value, in: range)
    }

    /// Checks an already-parsed value. Rejects NaN and infinity explicitly —
    /// `Double("nan")` and `Double("inf")` both parse, and both survive a naive
    /// `> 0` check.
    static func validate(_ value: Double, in range: ClosedRange<Double>) -> Double? {
        guard value.isFinite, range.contains(value) else { return nil }
        return value
    }

    /// The message shown when a typed value is out of range, phrased as the
    /// bounds rather than as a scolding.
    static func rangeHint(_ range: ClosedRange<Double>, unit: String) -> String {
        "Enter a value between \(format(range.lowerBound)) and \(format(range.upperBound)) \(unit)."
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

// MARK: - Display Rounding

extension Double {

    /// Body weight as it should be shown: always one decimal place.
    ///
    /// `formatted1` drops the decimal on whole numbers, so a list of weights
    /// renders as "75", "75.4", "76" — three different widths, and a stored
    /// 75.04 and a stored 75 look identical. Weight is stored at full `Double`
    /// precision and rounded only here, at the point of display, to one fixed
    /// decimal. One rule, applied everywhere a weight appears.
    var weightDisplay: String { String(format: "%.1f", self) }

    /// A percentage to one decimal place, for body fat.
    var percentDisplay: String { String(format: "%.1f", self) }
}
