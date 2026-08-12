import Foundation

/// Apple's pipeline and bundle identifiers, made readable. Unknown values fall back to a
/// mechanical prettifier rather than being hidden — a new pipeline should still show up.
public enum DisplayNames {
    private static let pipelines: [String: String] = [
        "Embedding": "Embedding (semantic vectors)",
        "Keyphrase": "Keyphrases",
        "LSSR5EventsandordersUrgent": "Events & orders (urgent)",
        "LSSR5EventsandordersBackground": "Events & orders (background)",
        "LSSR5IdentificationdocumentsBackground": "ID documents (background)",
    ]

    public static func pipeline(for identifier: String) -> String {
        if let known = pipelines[identifier] { return known }
        return splitCamelCase(identifier.replacingOccurrences(of: "LSSR5", with: ""))
    }

    /// Same pipelines, named for a widget row rather than a menu — roughly 18 characters before the
    /// percentage on the right starts losing its column.
    private static let shortPipelines: [String: String] = [
        "Embedding": "Embedding",
        "Keyphrase": "Keyphrases",
        "LSSR5EventsandordersUrgent": "Events (urgent)",
        "LSSR5EventsandordersBackground": "Events (backgr.)",
        "LSSR5IdentificationdocumentsBackground": "ID documents",
    ]

    public static func shortPipeline(for identifier: String) -> String {
        shortPipelines[identifier] ?? pipeline(for: identifier)
    }

    private static let apps: [String: String] = [
        "all": "All apps",
        "com.apple.mail": "Mail",
        "com.apple.MobileSMS": "Messages",
        "com.apple.Notes": "Notes",
        "com.apple.CalendarUI": "Calendar",
        "com.apple.Safari": "Safari",
        "com.apple.helpviewer": "Help Viewer",
        "com.apple.reminders": "Reminders",
        "com.apple.freeform": "Freeform",
        "com.apple.shortcuts": "Shortcuts",
        "com.apple.systempreferences": "System Settings",
        "com.apple.contactsd": "Contacts",
        "com.apple.mobilephone": "Phone",
        "com.apple.podcasts": "Podcasts",
        "com.apple.AppStore": "App Store",
        "com.apple.tips": "Tips",
        "com.apple.appplaceholdersyncd": "App placeholders",
        "com.apple.spotlight.events": "Spotlight events",
    ]

    public static func app(for bundleID: String) -> String {
        if let known = apps[bundleID] { return known }
        guard let last = bundleID.split(separator: ".").last else { return bundleID }
        return splitCamelCase(String(last))
    }

    /// `EventsandordersUrgent` → `Eventsandorders Urgent`. Crude on purpose: it only has to make an
    /// unmapped identifier legible, not guess Apple's intended wording.
    private static func splitCamelCase(_ input: String) -> String {
        var out = ""
        for (index, character) in input.enumerated() {
            if index > 0, character.isUppercase { out.append(" ") }
            out.append(character)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
