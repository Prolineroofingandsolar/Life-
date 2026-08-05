import Foundation

// MARK: - Health Provider

/// The one place a data provider is named.
///
/// The app had grown three vocabularies for the same two things. "Fitbit",
/// "Google Health", "Google" and "the band" all meant the record came from a
/// Fitbit device read through Google's Health API; "Apple Health", "HealthKit"
/// and "iPhone" all meant the record came from HealthKit. Which word appeared
/// depended on which screen you were looking at, so it read as though there
/// were four or five sources rather than two.
///
/// Every user-facing mention of a provider now resolves through this type.
/// `displayName` is what a person reads, `storageValue` is what gets written to
/// a record's `source` field, and `init(storageValue:)` reads back everything
/// the older builds wrote so historic entries still name themselves correctly.
enum HealthProvider: String, Codable, CaseIterable, Identifiable, Sendable {

    /// A Fitbit device, read through Google's Health API. Named for the device
    /// the user owns, not for the API in between — nobody wears a Google.
    case fitbit
    /// Apple Health, whatever wrote into it.
    case appleHealth
    /// Typed in by hand.
    case manual
    /// Derived by Life from other stored values rather than imported.
    case calculated

    var id: String { rawValue }

    /// What the user reads. The only correct spelling of each provider.
    var displayName: String {
        switch self {
        case .fitbit:      return "Fitbit"
        case .appleHealth: return "Apple Health"
        case .manual:      return "Entered manually"
        case .calculated:  return "Calculated by Life"
        }
    }

    /// A short form for tight spaces — chips, table cells, inline captions.
    var shortName: String {
        switch self {
        case .fitbit:      return "Fitbit"
        case .appleHealth: return "Apple Health"
        case .manual:      return "Manual"
        case .calculated:  return "Calculated"
        }
    }

    /// The full attribution, naming the route as well as the device. Used where
    /// there's room to be precise about how the number arrived.
    var detailedName: String {
        switch self {
        case .fitbit:      return "Fitbit Direct"
        case .appleHealth: return "Apple Health"
        case .manual:      return "Entered manually"
        case .calculated:  return "Calculated by Life"
        }
    }

    var iconName: String {
        switch self {
        case .fitbit:      return "figure.walk.motion"
        case .appleHealth: return "heart.fill"
        case .manual:      return "square.and.pencil"
        case .calculated:  return "function"
        }
    }

    /// The value stored on a record's `source` field.
    var storageValue: String { rawValue }

    /// Reads back every spelling any build of this app has ever written to a
    /// `source` field, so old records don't fall through to "unknown".
    init?(storageValue raw: String?) {
        guard let raw else { return nil }
        switch raw.lowercased().replacingOccurrences(of: " ", with: "") {
        case "fitbit", "google", "googlehealth", "googlefit", "googlehealthapi":
            self = .fitbit
        case "applehealth", "healthkit", "apple", "iphone", "watch", "applewatch":
            self = .appleHealth
        case "manual", "manuallyentered", "user", "typed":
            self = .manual
        case "calculated", "derived", "estimate", "estimated":
            self = .calculated
        default:
            return nil
        }
    }

    /// Names a stored `source` string for display, falling back to the raw text
    /// rather than inventing an attribution for something unrecognised.
    static func describe(_ raw: String?) -> String {
        if let provider = HealthProvider(storageValue: raw) { return provider.detailedName }
        guard let raw, !raw.isEmpty else { return "Unknown source" }
        return raw
    }
}
