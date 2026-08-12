import SiriIndexCore
import SwiftUI

/// The panel shown when the menu bar item is clicked.
struct StatusPanel: View {
    let store: StatusStore
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if store.needsFullDiskAccess {
                fullDiskAccessState
            } else if store.status.pipelines.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(store.status.pipelines) { pipeline in
                        PipelineRow(
                            pipeline: pipeline,
                            isExpanded: expanded.contains(pipeline.id),
                            toggle: { toggle(pipeline.id) }
                        )
                    }
                }
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 380)
        .task { await store.refresh() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Semantic Index")
                .font(.headline)
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(store.status.updaterRunning ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(store.status.updaterRunning ? "Indexer running" : "Indexer idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// macOS keeps `~/Library/Metadata/CoreSpotlight` behind TCC, so a freshly built bundle reads
    /// nothing until it is added to Full Disk Access by hand (ADR-0004). There is no API to
    /// request this permission — the only route is the Settings pane.
    private var fullDiskAccessState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Full Disk Access required", systemImage: "lock.fill")
                .font(.callout.weight(.medium))

            Text("macOS protects the indexing reports in ~/Library/Metadata/CoreSpotlight. "
                 + "Add this app under Privacy & Security → Full Disk Access, then quit and reopen it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Open Full Disk Access") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
                    NSWorkspace.shared.open(url)
                }
                Button("Reveal App") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No completeness reports found.")
                .font(.callout)
            Text(store.lastError ?? "macOS writes these only once Apple Intelligence indexing has begun.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let age = store.status.age() {
                    Text("Reported \(Formatting.age(age))")
                } else {
                    Text("Never reported")
                }
                Text("macOS refreshes these figures roughly daily.")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Refresh") { Task { await store.refresh() } }
                .disabled(store.isRefreshing)
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

private struct PipelineRow: View {
    let pipeline: PipelineProgress
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(pipeline.displayName)
                        .font(.callout)
                    Spacer()
                    Text(Formatting.percent(pipeline.completeness))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(pipeline.completeness >= 0.999 ? .secondary : .primary)
                }
            }
            .buttonStyle(.plain)

            ProgressView(value: min(max(pipeline.completeness, 0), 1))
                .progressViewStyle(.linear)

            Text("\(Formatting.itemCount(pipeline.eligibleItems)) items\(pipeline.headlineIsDerived ? " · estimated" : "")")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(pipeline.laggards.prefix(8)) { app in
                        HStack {
                            Text(app.displayName)
                                .font(.caption)
                            Spacer()
                            Text("\(Formatting.percent(app.completeness)) of \(Formatting.itemCount(app.eligibleItems))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if pipeline.laggards.isEmpty {
                        Text("All donating apps complete.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 14)
                .padding(.top, 2)
            }
        }
    }
}
