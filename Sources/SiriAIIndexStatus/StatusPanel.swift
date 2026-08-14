import SiriIndexCore
import SwiftUI

/// The panel shown when the menu bar item is clicked.
struct StatusPanel: View {
    let store: StatusStore
    @State private var expanded: Set<String> = []
    @State private var showingAll: Set<String> = []
    @State private var showingSchedule = false
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if store.needsFullDiskAccess {
                fullDiskAccessState
            } else if store.status.pipelines.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    searchField

                    if trimmedQuery.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(store.status.pipelines) { pipeline in
                                PipelineRow(
                                    pipeline: pipeline,
                                    isExpanded: expanded.contains(pipeline.id),
                                    isShowingAll: showingAll.contains(pipeline.id),
                                    toggle: { toggle(&expanded, pipeline.id) },
                                    toggleShowAll: { toggle(&showingAll, pipeline.id) }
                                )
                            }
                        }
                    } else {
                        appResults
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

    /// The developer entry point: type a bundle ID, see what the index has of that app.
    ///
    /// Searching the raw identifier matters more than searching the pretty name — a developer knows
    /// `com.example.MyApp` and has never seen what `DisplayNames` makes of it.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Find an app or bundle ID", text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }

    private var appResults: some View {
        let matches = store.status.appStandings(matching: trimmedQuery)
        return VStack(alignment: .leading, spacing: 14) {
            if matches.isEmpty {
                noMatchState
            } else {
                ForEach(matches.prefix(Self.maxResults)) { standing in
                    AppStandingCard(standing: standing)
                }
                if matches.count > Self.maxResults {
                    Text("\(matches.count - Self.maxResults) more match — narrow the search.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static let maxResults = 10

    /// An app being absent is a real answer, and the two reasons for it are not the same problem —
    /// so say both rather than leaving a developer to conclude their donations were rejected.
    private var noMatchState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No app matching “\(trimmedQuery)” appears in any report.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("An app shows up here once the indexer has picked up items it donated. "
                 + "These reports are written about once a day, so a donation made since the last "
                 + "run has not been counted yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                // The info button rides the short line, not the sentence below it: the sentence is
                // the first thing to be truncated when the buttons claim their width, and a control
                // that disappears at narrow widths is worse than no control.
                HStack(spacing: 4) {
                    if let age = store.status.age() {
                        Text("Reported \(Formatting.age(age))")
                    } else {
                        Text("Never reported")
                    }
                    Button {
                        showingSchedule.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .help("When these figures update")
                    .popover(isPresented: $showingSchedule, arrowEdge: .bottom) {
                        schedulePopover
                    }
                }
                Text("macOS refreshes these figures daily.")
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .layoutPriority(1)

            Spacer(minLength: 8)

            Button("Refresh") { Task { await store.refresh() } }
                .disabled(store.isRefreshing)
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    /// Everything here is measured, not guessed — the schedule is declared in
    /// `com.apple.spotlightknowledged.updater.plist`; see
    /// `docs/notes/20260812-what-schedules-the-completeness-reports.md`.
    ///
    /// The last point is the one worth the popover: "Refresh" re-reads the files on disk, which is
    /// not what most people will assume it does, and there is no button anywhere on the system that
    /// does the other thing.
    private var schedulePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When these figures update")
                .font(.callout.weight(.semibold))

            VStack(alignment: .leading, spacing: 7) {
                schedulePoint(
                    "calendar",
                    "Once a day. macOS runs a background task every 24 hours to write these reports; "
                        + "between runs the numbers do not move, however hard the indexer is working."
                )
                schedulePoint(
                    "powerplug",
                    "Only while plugged in. The task requires external power, so on battery the "
                        + "figures stay frozen — an unchanged percentage then says nothing about indexing."
                )
                schedulePoint(
                    "lock.open",
                    "The Mac must have been unlocked since it last started up."
                )
                schedulePoint(
                    "clock.badge.exclamationmark",
                    "24 hours is the shortest interval, not a promise. macOS runs the task at low "
                        + "priority and defers it under load."
                )
            }

            Divider()

            Text("Refresh re-reads the reports already on disk. Nothing can ask macOS to write new "
                 + "ones — the system blocks that even with administrator rights.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 330, alignment: .leading)
    }

    private func schedulePoint(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .center)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggle(_ set: inout Set<String>, _ id: String) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }
}

/// What the index holds for one bundle identifier, pipeline by pipeline.
///
/// Both halves are the point: the pipelines carrying rows, and the pipelines carrying none. A
/// developer reading this wants to know whether their donations were picked up at all before they
/// care how far along they are.
private struct AppStandingCard: View {
    let standing: AppStanding

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(standing.displayName)
                    .font(.callout.weight(.medium))
                Spacer()
                if standing.isCompleteEverywhere {
                    Text("fully indexed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Selectable, because the next thing a developer does with a bundle ID is paste it.
            Text(standing.bundleID)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(standing.standings) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.displayName)
                            .font(.caption)
                        Spacer(minLength: 8)
                        Text("\(Formatting.percent(row.completeness)) · \(Formatting.itemCount(row.indexedItems)) of \(Formatting.itemCount(row.eligibleItems))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(row.isComplete ? .secondary : .primary)
                    }
                }

                ForEach(standing.absentFromPipelines, id: \.self) { pipeline in
                    HStack(alignment: .firstTextBaseline) {
                        Text(DisplayNames.pipeline(for: pipeline))
                            .font(.caption)
                        Spacer(minLength: 8)
                        Text("no rows")
                            .font(.caption)
                    }
                    .foregroundStyle(.tertiary)
                    .help("This pipeline's report carries no row for \(standing.bundleID) — it has "
                          + "either donated nothing this pipeline considers eligible, or nothing yet.")
                }
            }
            .padding(.leading, 2)
        }
    }
}

private struct PipelineRow: View {
    let pipeline: PipelineProgress
    let isExpanded: Bool
    let isShowingAll: Bool
    let toggle: () -> Void
    let toggleShowAll: () -> Void

    /// Collapsed, this is the ranked backlog. Expanded to everything, it is the full donor list —
    /// including the apps at 100%, which `laggards` drops and a developer needs to see.
    private var visibleApps: [AppProgress] {
        isShowingAll ? pipeline.appsByRemainingItems : Array(pipeline.laggards.prefix(8))
    }

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
                    ForEach(visibleApps) { app in
                        HStack {
                            Text(app.displayName)
                                .font(.caption)
                            Spacer()
                            Text("\(Formatting.percent(app.completeness)) of \(Formatting.itemCount(app.eligibleItems))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .help(app.bundleID)
                    }
                    if visibleApps.isEmpty {
                        Text("All donating apps complete.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if pipeline.apps.count > visibleApps.count || isShowingAll {
                        Button(isShowingAll
                               ? "Show backlog only"
                               : "Show all \(pipeline.apps.count) donating apps") {
                            toggleShowAll()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 2)
                    }
                }
                .padding(.leading, 14)
                .padding(.top, 2)
            }
        }
    }
}
