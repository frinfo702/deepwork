import SwiftUI
import AppKit

/// The settings sheet: a chrome-free glass window that still keeps native
/// traffic lights, key-window behavior and keyboard shortcuts.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(store: Store, updater: Updater) {
        let window = self.window ?? makeWindow(store: store, updater: updater)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(store: Store, updater: Updater) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Deepwork Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 860, height: 650)
        window.contentMaxSize = NSSize(width: 860, height: 650)

        window.contentView = NSHostingView(rootView: SettingsView()
            .environmentObject(store)
            .environmentObject(updater)
            .ignoresSafeArea()
        )
        window.center()
        return window
    }
}
