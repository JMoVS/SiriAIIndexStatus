// Desktop widget for the semantic index.
//
// Built as a WidgetKit extension by SiriAIIndexStatus.xcodeproj, embedded in the host app under
// Contents/PlugIns/ (ADR-0005). SwiftPM cannot produce an .appex, so this file is not part of any
// Package.swift target — `swift build` does not compile it.
//
// The extension is sandboxed and has no Full Disk Access of its own, so it never reads the report
// directory: the host app publishes a snapshot into the shared App Group container and the widget
// only reads that (ADR-0005). It also holds no arithmetic — every number comes from SiriIndexCore,
// so the widget and the menu bar item cannot disagree (ADR-0001).

import SiriIndexCore
import SwiftUI
import WidgetKit

struct IndexStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: SnapshotStore.Snapshot?
    /// Set when there is nothing to show: no snapshot written yet, no App Group container, or the
    /// host app's own read failed. The widget cannot open Settings or request TCC (ADR-0004), so
    /// saying why is the whole of what it can do.
    let failure: String?

    var status: IndexStatus { snapshot?.status ?? .empty }

    /// A snapshot much older than the app's 10-minute poll means the app is not running — a
    /// different problem from indexing having stalled, and worth distinguishing on screen.
    var appLooksStopped: Bool { (snapshot?.staleness(now: date) ?? 0) > 3600 }
}

struct IndexStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> IndexStatusEntry {
        IndexStatusEntry(date: Date(), snapshot: nil, failure: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (IndexStatusEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<IndexStatusEntry>) -> Void) {
        // Reports refresh roughly daily (ADR-0002) and the app reloads this timeline whenever a
        // number actually moves, so hourly is only a backstop for the app not running.
        let next = Date().addingTimeInterval(3600)
        completion(Timeline(entries: [load()], policy: .after(next)))
    }

    private func load() -> IndexStatusEntry {
        do {
            let snapshot = try SnapshotStore.read()
            return IndexStatusEntry(date: Date(), snapshot: snapshot, failure: snapshot.failure)
        } catch {
            return IndexStatusEntry(date: Date(), snapshot: nil, failure: error.localizedDescription)
        }
    }
}

struct IndexStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: IndexStatusEntry

    var body: some View {
        Group {
            if family == .systemSmall || entry.status.headline == nil {
                summary
            } else {
                // Two columns rather than one tall stack: the headline, the four supporting
                // pipelines and the age line do not fit above one another in a medium widget, and
                // a VStack that overflows silently drops the title and the age — the two parts
                // that say what the number is and how old it is.
                HStack(alignment: .top, spacing: 12) {
                    summary
                        .frame(width: 118, alignment: .leading)
                    Divider()
                    pipelineList
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("Semantic Index")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if entry.status.updaterRunning {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Indexer running")
                }
            }

            if let headline = entry.status.headline {
                Text(Formatting.percent(headline.completeness))
                    .font(.system(size: family == .systemSmall ? 34 : 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                // The big number belongs to one pipeline, not to the index as a whole — unlabelled
                // beside a list of four other pipelines it reads as a total (ADR-0003).
                Text(headline.shortDisplayName)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                Text("\(Formatting.itemCount(headline.eligibleItems)) items")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if let failure = entry.failure {
                Text(failure)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No reports yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            footer
        }
    }

    private var pipelineList: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(entry.status.supporting) { pipeline in
                HStack(spacing: 6) {
                    Text(pipeline.shortDisplayName)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text(Formatting.percent(pipeline.completeness))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Two different kinds of "old" share this line, and only one of them is about indexing:
    /// the report's own age, or the app having stopped publishing.
    @ViewBuilder
    private var footer: some View {
        if entry.appLooksStopped, entry.snapshot != nil {
            Label("App not running", systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if entry.failure != nil, entry.status.headline != nil {
            Label("Last good reading", systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let age = entry.status.age(now: entry.date) {
            Text(Formatting.age(age))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

@main
struct IndexStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "de.justinscholz.SiriAIIndexStatus.widget", provider: IndexStatusProvider()) { entry in
            IndexStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Semantic Index")
        .description("How far along Apple Intelligence's on-device index is.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
