import SiriIndexCore
import SwiftUI

/// The panel shown when the menu bar item is clicked.
struct StatusPanel: View {
    let store: StatusStore
    @State private var expanded: Set<String>
    @State private var showingAll: Set<String> = []
    @State private var showingSchedule = false
    @State private var query = ""
    /// Height of the pipeline list's content, so the scroll view can stop at it.
    @State private var listContentHeight: CGFloat = 0

    /// `initiallyExpanded` exists for `PanelSnapshot`: the layout that overflows is the expanded
    /// one, and a harness that can only render the collapsed panel cannot see the bug it is for.
    init(store: StatusStore, initiallyExpanded: Set<String> = []) {
        self.store = store
        _expanded = State(initialValue: initiallyExpanded)
    }

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
                    // Outside the scroll view: the search field is how you escape a long list, so
                    // it must not be the first thing that scrolls away.
                    searchField

                    ScrollView {
                        Group {
                            if trimmedQuery.isEmpty {
                                VStack(alignment: .leading, spacing: 14) {
                                    ForEach(store.status.pipelines) { pipeline in
                                        PipelineRow(
                                            pipeline: pipeline,
                                            delta: store.delta?[pipeline.id],
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
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            listContentHeight = $0
                        }
                    }
                    // A scroll view takes every point it is offered, so a plain `maxHeight` would
                    // pad a short list out to the cap with empty space. It has to be told the
                    // height its own content wants.
                    .frame(height: listContentHeight > 0
                           ? min(listContentHeight, Self.listHeightCap)
                           : nil)
                    .scrollBounceBehavior(.basedOnSize)
                }
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 380)
        .task { await store.refresh() }
    }

    /// How tall the pipeline list may grow before it scrolls instead.
    ///
    /// A `MenuBarExtra` window sizes itself to its content and does not stop at the screen edge:
    /// expanding one pipeline's donor list ran the panel off the bottom, with the rows that were
    /// scrolled past simply unreachable. Measured against the screen rather than fixed, because
    /// the content that overflows is a list whose length depends on how many apps donate.
    private static var listHeightCap: CGFloat {
        // The chrome that must stay on screen with it: title, search field, divider, footer,
        // padding, and the menu bar the panel hangs from.
        let chrome: CGFloat = 200
        let available = (NSScreen.main?.visibleFrame.height ?? 800) - chrome
        return min(max(available, 280), 900)
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
                    AppStandingCard(standing: standing, delta: store.delta)
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
    /// Nil until the app has seen two reports — "did my donations move today" is the developer's
    /// second question, and it cannot be answered from a single checkpoint.
    let delta: IndexDelta?

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
                        if let moved = delta?[row.pipeline]?.app(standing.bundleID),
                           moved.isNew || moved.indexedItemsChange != 0 {
                            Text(moved.isNew
                                 ? "new"
                                 : Formatting.signedItemCount(moved.indexedItemsChange))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(moved.indexedItemsChange < 0 ? Color.secondary : Color.green)
                                .help(moved.isNew
                                      ? "This app carried no row in the previous report."
                                      : "Change since the previous report.")
                        }
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
    let delta: PipelineDelta?
    let isExpanded: Bool
    let isShowingAll: Bool
    let toggle: () -> Void
    let toggleShowAll: () -> Void

    /// Collapsed, this is the ranked backlog. Expanded to everything, it is the full donor list —
    /// including the apps at 100%, which `laggards` drops and a developer needs to see.
    private var visibleApps: [AppProgress] {
        isShowingAll ? pipeline.appsByRemainingItems : Array(pipeline.laggards.prefix(8))
    }

    /// The question a percentage on its own cannot answer: did anything happen since yesterday.
    ///
    /// Item count leads, percentage points follow. The eligible set grows as apps donate, so the
    /// percentage can fall on a day the indexer got through thousands of items — reporting only
    /// the percentage would call that day a regression.
    @ViewBuilder
    private func progressSinceLastReport(_ composition: PipelineComposition) -> some View {
        if let delta {
            if delta.hasMovement {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(Formatting.signedItemCount(delta.indexedItemsChange))
                            .foregroundStyle(delta.indexedItemsChange < 0 ? Color.secondary : Color.green)
                        Text("indexed in \(Formatting.duration(delta.span)) · \(Formatting.percent(delta.previousCompleteness)) → \(Formatting.percent(delta.currentCompleteness))")
                            .foregroundStyle(.secondary)
                    }
                    // Spelled out rather than "+2,073 eligible", which reads as the size of the
                    // backlog instead of the growth of it. "The total" is the item count on the
                    // line above — the same number the percentage is measured against.
                    if delta.eligibleItemsChange > 0 {
                        Text("\(Formatting.itemCount(delta.eligibleItemsChange)) more items added to the total")
                            .foregroundStyle(.secondary)
                    } else if delta.eligibleItemsChange < 0 {
                        Text("\(Formatting.itemCount(-delta.eligibleItemsChange)) items removed from the total")
                            .foregroundStyle(.secondary)
                    }
                    // Without this the percentage above is read as indexing either way. Measured
                    // 2026-09-08: Embedding fell 51.3% → 47.3% on a day whose entire movement was
                    // one donor re-counting what it considers eligible (WL-12, WL-13).
                    if composition.isDominatedByScopeChange {
                        Label(
                            "Mostly the total being resized, not indexing",
                            systemImage: "arrow.left.and.right"
                        )
                        .foregroundStyle(.secondary)
                        .help("The eligible total moved further than the indexed count did, so most "
                              + "of the change in percentage is a change in what is being counted.")
                    }
                }
                .font(.caption.monospacedDigit())
                .help("Measured between the last two reports macOS wrote, "
                      + "\(Formatting.duration(delta.span)) apart.")
            } else {
                Text("No change in the \(Formatting.duration(delta.span)) to this report")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("First reading — progress appears after the next report")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .help("macOS overwrites these reports in place, so the app can only compare "
                      + "checkpoints it was running to see.")
        }
    }

    /// The answer to "it says 47% and never moves".
    ///
    /// Each donor's figure is `share of the total × how far it still has to go`, so the column
    /// sums exactly to the missing percentage — this is a decomposition of the headline, not a
    /// second ranking beside it. Measured 2026-09-10: Mail alone holds 38.9 of Embedding's missing
    /// 52.7, and 6.2 more sit in 13,069 Help Viewer documents that have not moved in 17 days.
    /// See `docs/notes/20260911-what-the-headline-percentage-measures.md`.
    @ViewBuilder
    private func composition(_ composition: PipelineComposition) -> some View {
        let principals = composition.principals(limit: 3)
        // One donor holding everything is already obvious from the expanded list; the block earns
        // its lines only when the headline is a blend of donors pulling different ways.
        if pipeline.completeness < 0.999, principals.rows.count > 1 {
            VStack(alignment: .leading, spacing: 2) {
                Text("Where the missing \(Formatting.percent(1 - pipeline.completeness)) sits")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                ForEach(principals.rows) { donor in
                    HStack(spacing: 6) {
                        Text(donor.displayName)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Text(Formatting.points(donor.withheld))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        movement(donor.movement)
                            .frame(minWidth: 78, alignment: .trailing)
                    }
                    .help("\(donor.bundleID) — \(Formatting.percent(donor.share)) of this "
                          + "pipeline's items, \(Formatting.percent(donor.completeness)) done. "
                          + "Finishing it would add \(Formatting.points(donor.withheld)) points "
                          + "to the figure above.")
                }

                if principals.otherCount > 0, principals.otherWithheld >= 0.000_5 {
                    HStack(spacing: 6) {
                        Text("\(principals.otherCount) others")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text(Formatting.points(principals.otherWithheld))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Spacer().frame(width: 78)
                    }
                }
            }
            .font(.caption2)
        }
    }

    /// Work and scope change are both "movement" and only one of them is indexing, so they never
    /// get the same colour: green is reserved for items that actually went into the index.
    @ViewBuilder
    private func movement(_ movement: DonorMovement) -> some View {
        switch movement {
        case .indexed(let items):
            Text(Formatting.signedItemCount(items))
                .monospacedDigit()
                .foregroundStyle(items < 0 ? Color.secondary : Color.green)
                .help("Items indexed since the previous report.")
        case .scopeChanged(let eligibleItems, _):
            Text("total \(Formatting.signedItemCount(eligibleItems))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("This donor's eligible set changed size by more than it indexed — the "
                      + "percentage moved without the work behind it.")
        case .arrived:
            Text("new")
                .foregroundStyle(.secondary)
                .help("No row in the previous report.")
        case .still:
            Text("no change")
                .foregroundStyle(.tertiary)
                .help("Neither indexed nor eligible count moved since the previous report.")
        case .unknown:
            EmptyView()
        }
    }

    var body: some View {
        let composed = pipeline.composition(delta: delta)
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

            progressSinceLastReport(composed)
            composition(composed)

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
                            if let moved = delta?.app(app.bundleID), moved.isNew || moved.indexedItemsChange != 0 {
                                Text(moved.isNew ? "new" : Formatting.signedItemCount(moved.indexedItemsChange))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(moved.indexedItemsChange < 0 ? Color.secondary : Color.green)
                                    .frame(minWidth: 42, alignment: .trailing)
                            }
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
