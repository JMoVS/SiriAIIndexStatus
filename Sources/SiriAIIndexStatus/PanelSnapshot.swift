import AppKit
import SiriIndexCore
import SwiftUI

/// Renders the panel to a PNG and exits, when `SIIS_RENDER_PANEL` names a path.
///
/// The panel lives in a `MenuBarExtra`, which cannot be opened from a script: with a menu bar
/// manager installed the status item is not even on screen, and `screencapture` needs a session
/// that is unlocked and awake. Neither is available to an agent checking its own layout, and
/// "it compiled" is not a claim that a view fits in 380 points. This is the way to see it.
///
/// `ImageRenderer` cannot draw every view: `ProgressView` and `TextField` come out as a solid
/// block with a "no entry" glyph. That is the renderer, not the panel — everything the layout
/// check is for (wrapping, truncation, column alignment, overall height) is faithful.
///
/// `SIIS_RENDER_EXPANDED` takes a comma-separated list of pipeline identifiers to draw expanded,
/// e.g. `Embedding`. The collapsed panel fits on any screen; the expanded one is what overflows.
///
/// Development only — nothing calls it unless the variable is set.
enum PanelSnapshot {
    static var isRequested: Bool { path != nil }

    private static var path: String? {
        ProcessInfo.processInfo.environment["SIIS_RENDER_PANEL"]
    }

    /// Pipelines to draw expanded, from `SIIS_RENDER_EXPANDED`.
    ///
    /// Read by the live app too, not only the renderer: `ImageRenderer` makes a single layout pass,
    /// so the scroll view's measured height never feeds back into it and an offscreen render always
    /// draws the list at full length. Checking that the window actually stops at the screen edge
    /// takes the running app — which needs a way to start with a pipeline open, because the status
    /// item is hidden behind a menu bar manager and cannot be clicked by a script.
    static var initiallyExpanded: Set<String> {
        ProcessInfo.processInfo.environment["SIIS_RENDER_EXPANDED"]
            .map { Set($0.split(separator: ",").map(String.init)) } ?? []
    }

    @MainActor
    static func renderIfRequested(_ store: StatusStore) async {
        guard let path else { return }

        // Render real data, not a fixture: the layout only breaks on the numbers the machine
        // actually has — 22 donors, six-figure item counts, long bundle identifiers.
        await store.refresh()

        let renderer = ImageRenderer(
            content: StatusPanel(store: store, initiallyExpanded: initiallyExpanded)
        )
        renderer.scale = 2

        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(
                  URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil
              )
        else {
            FileHandle.standardError.write(Data("could not render panel\n".utf8))
            exit(1)
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        exit(0)
    }
}
