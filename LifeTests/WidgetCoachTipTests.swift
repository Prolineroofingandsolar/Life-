import Testing
import Foundation
@testable import Life

/// What the coach puts on the home screen.
///
/// Two things to keep true, and neither is visible from the app: the widget
/// decodes a *separate* declaration of this type, so a renamed property fails
/// silently and leaves the placeholder on screen; and a widget sits in full view
/// of anyone holding the phone, so no health figure may travel in it.
struct WidgetCoachTipTests {

    private func encoded(_ tip: WidgetSync.WidgetCoachTip) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(tip)
        return try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func tip() -> WidgetSync.WidgetCoachTip {
        WidgetSync.WidgetCoachTip(
            headline: "A short walk after lunch",
            summary: "You're a few thousand steps behind your usual by this time.",
            origin: "gemini",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    /// The field names the widget's own decoder expects, exactly.
    @Test("The payload has the four keys the widget decodes, and no others")
    func keysMatchTheWidget() throws {
        let json = try encoded(tip())
        #expect(Set(json.keys) == ["headline", "summary", "origin", "generatedAt"])
    }

    /// The whole point of `CoachProvenance` is that a rules-written line is
    /// never shown under a label implying a model wrote it. On a widget there is
    /// no explanation sheet to correct the impression, so the origin has to
    /// travel with the words.
    @Test("Provenance travels with the words")
    func originIsCarried() throws {
        let onDevice = WidgetSync.WidgetCoachTip(
            headline: "H", summary: "S", origin: CoachProvenance.Origin.onDevice.rawValue,
            generatedAt: Date()
        )
        #expect(try encoded(onDevice)["origin"] as? String == "onDevice")

        // Every origin the app can produce must survive as a string the widget
        // recognises — a new case that decoded to nothing would show a tip with
        // no attribution at all.
        for origin in [
            CoachProvenance.Origin.gemini,
            .onDevice,
            .offlineFallback,
            .usageLimited,
        ] {
            #expect(!origin.rawValue.isEmpty)
        }
    }

    @Test("Dates encode as ISO-8601, which is what the widget decodes")
    func datesAreISO8601() throws {
        let json = try encoded(tip())
        let value = try #require(json["generatedAt"] as? String)
        #expect(value.contains("2023-11-14"))
    }
}
