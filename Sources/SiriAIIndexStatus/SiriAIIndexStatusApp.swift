import AppKit
import SiriIndexCore
import SwiftUI

@main
struct SiriAIIndexStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = StatusStore()

    var body: some Scene {
        MenuBarExtra {
            StatusPanel(store: store)
        } label: {
            // A menu bar label renders as a template image, so icon + text must be one HStack.
            HStack(spacing: 3) {
                Image(systemName: symbolName)
                if let headline = store.status.headline {
                    Text(Formatting.compactPercent(headline.completeness))
                }
            }
            .task { store.start() }
        }
        .menuBarExtraStyle(.window)
    }

    private var symbolName: String {
        guard !store.status.pipelines.isEmpty else { return "brain.head.profile" }
        return store.status.isComplete ? "brain.head.profile.fill" : "brain.head.profile"
    }
}

/// Keeps the app out of the Dock and the app switcher — it is a menu bar accessory only.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
