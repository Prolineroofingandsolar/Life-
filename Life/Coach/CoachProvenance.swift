import SwiftUI

// MARK: - Coach Provenance

/// Where a piece of coach output came from, and when.
///
/// This exists because the silent fallback was doing real damage in both
/// directions. When Gemini failed, the card quietly showed a rule-based line
/// under the same "AI coach" label — so the model looked ineffective, and the
/// rules got the blame for output they didn't write. When AI was switched off
/// entirely, the same label implied a model was running that wasn't. Either way
/// the user had no way to tell what they were reading, and no reason to trust
/// the next thing it said.
///
/// Provenance is carried with the output rather than reconstructed by the view,
/// because only the service knows which of the four paths was taken, and only it
/// knows whether the answer came off the cache.
struct CoachProvenance: Codable, Equatable, Sendable {

    enum Origin: String, Codable, Sendable {
        /// Written by the model.
        case gemini
        /// Written by `LocalCoach` because cloud AI is off or not consented to.
        /// A deliberate mode, not a failure — labelled as such.
        case onDevice
        /// Cloud AI is on, was tried, and didn't work. The suggestion below is
        /// still useful; it just isn't the one that was asked for.
        case offlineFallback
        /// Cloud AI is on and affordable calls have run out for the period.
        case usageLimited
    }

    var origin: Origin
    /// When the words were produced. For cached output this is the original
    /// generation time, not the moment it was read back.
    var generatedAt: Date
    /// True when this came from the cache rather than a fresh call.
    var wasCached: Bool = false
    /// When the health figures behind it last arrived. Distinct from
    /// `generatedAt`: advice written a minute ago from data six hours old is
    /// six hours old.
    var dataUpdatedAt: Date?

    /// A short, already-sanitised explanation of what went wrong.
    ///
    /// Never a raw backend error. `CoachError.errorDescription` is written for a
    /// person and carries no status codes, request bodies, endpoints or
    /// credentials — see `HTTPCoachTransport`, which discards the response body
    /// on failure precisely so nothing from it can reach here.
    var failureNote: String?
    /// Whether pressing Retry could plausibly change the outcome. A spend
    /// ceiling or a switched-off feature fails identically on the second go.
    var isRetryable: Bool = false

    // MARK: Labels

    /// The line under the card. One of the five the brief asks for.
    var primaryLabel: String {
        let time = generatedAt.formatted(date: .omitted, time: .shortened)
        if wasCached {
            switch origin {
            case .gemini:  return "Gemini · cached from \(time)"
            default:       return "On-device suggestion · cached from \(time)"
            }
        }
        switch origin {
        case .gemini:          return "Gemini · updated \(time)"
        case .onDevice:        return "On-device suggestion"
        case .offlineFallback: return "Offline suggestion · Gemini unavailable"
        case .usageLimited:    return "On-device suggestion · AI limit reached"
        }
    }

    /// When the *data* was last refreshed, which is a separate claim from when
    /// the words were written and is the one people actually act on.
    var dataLabel: String? {
        guard let dataUpdatedAt else { return nil }
        return "Based on data updated \(dataUpdatedAt.formatted(date: .omitted, time: .shortened))"
    }

    /// Whether the label should be drawn in a colour that says "read me".
    var needsAttention: Bool {
        origin == .offlineFallback || origin == .usageLimited
    }

    var accessibilityLabel: String {
        [primaryLabel, dataLabel, failureNote]
            .compactMap { $0 }
            .joined(separator: ". ")
    }

    // MARK: Construction

    static func local(at date: Date = Date(), dataUpdatedAt: Date? = nil) -> CoachProvenance {
        .init(origin: .onDevice, generatedAt: date, dataUpdatedAt: dataUpdatedAt)
    }

    static func cloud(at date: Date = Date(), dataUpdatedAt: Date? = nil) -> CoachProvenance {
        .init(origin: .gemini, generatedAt: date, dataUpdatedAt: dataUpdatedAt)
    }
}

// MARK: - Provenance view

/// The provenance line, drawn the same way everywhere it appears.
///
/// One view rather than three near-identical `Text` stacks, because the point of
/// the label is that it means the same thing on the card, the briefing and the
/// explanation sheet. Three copies is three chances for one of them to keep
/// saying "AI coach" after the others stopped.
struct CoachProvenanceLabel: View {

    let provenance: CoachProvenance
    /// Shown when retrying is worth offering. Nil hides the button entirely
    /// rather than disabling it — a Retry that can't help is noise.
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .accessibilityHidden(true)
                Text(provenance.primaryLabel)
                    .font(.caption2)
            }
            .foregroundColor(provenance.needsAttention ? .orange : Color(.tertiaryLabel))

            if let dataLabel = provenance.dataLabel {
                Text(dataLabel)
                    .font(.caption2)
                    .foregroundColor(Color(.tertiaryLabel))
            }

            if let note = provenance.failureNote {
                Text(note)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if provenance.isRetryable, let onRetry {
                Button("Try Gemini again", action: onRetry)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppTheme.primary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(provenance.accessibilityLabel)
    }

    private var icon: String {
        switch provenance.origin {
        case .gemini:          return provenance.wasCached ? "clock.arrow.circlepath" : "sparkles"
        case .onDevice:        return "iphone"
        case .offlineFallback: return "wifi.slash"
        case .usageLimited:    return "gauge.with.dots.needle.33percent"
        }
    }
}
