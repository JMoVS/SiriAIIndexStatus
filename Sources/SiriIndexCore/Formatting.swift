import Foundation

/// Shared between the menu bar app and the widget so both phrase the same number identically.
public enum Formatting {
    /// `48.7%` — one decimal, because the interesting movement is sub-percent over hours.
    public static func percent(_ fraction: Double) -> String {
        String(format: "%.1f%%", (fraction * 100).rounded(toPlaces: 1))
    }

    /// `49%` — the menu bar title has no room for a decimal.
    public static func compactPercent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    public static func itemCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    /// `3 h ago`, `2 d ago` — report freshness, which the UI must show because the numbers are
    /// checkpoints rather than a live feed (ADR-0002).
    public static func age(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = interval < 3600 ? [.minute] : (interval < 86400 ? [.hour] : [.day, .hour])
        formatter.maximumUnitCount = 2
        let text = formatter.string(from: max(interval, 60)) ?? "?"
        return "\(text) ago"
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
