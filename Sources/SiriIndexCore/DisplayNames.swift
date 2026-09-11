import AppKit
import Foundation
import os

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
        if let installed = installedAppName(for: bundleID) { return installed }
        guard let last = bundleID.split(separator: ".").last else { return bundleID }
        return splitCamelCase(String(last))
    }

    /// Names resolved from LaunchServices, and the identifiers known to resolve to nothing.
    ///
    /// A failed lookup is cached as an empty string rather than retried: the panel redraws on every
    /// refresh, and an app that is not installed is not going to become installed between frames.
    private static let installedNames = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    /// Ask LaunchServices what the operator calls this app.
    ///
    /// The mechanical fallback turns `com.nextcloud.desktopclient` into "desktopclient", which is
    /// not a thing anyone has on their Mac. The table above only covers Apple's own bundles, and it
    /// never will cover the third-party donors — those are whatever the operator installed.
    private static func installedAppName(for bundleID: String) -> String? {
        if let cached = installedNames.withLock({ $0[bundleID] }) {
            return cached.isEmpty ? nil : cached
        }

        // Outside the lock: this is a LaunchServices round trip, not a dictionary read.
        let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path) }
            .map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 }

        installedNames.withLock { $0[bundleID] = resolved ?? "" }
        return resolved
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
