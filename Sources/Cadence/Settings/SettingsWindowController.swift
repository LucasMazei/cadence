import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(store: CadenceStore) {
        if let window {
            window.contentViewController = NSHostingController(
                rootView: SettingsView().environmentObject(store)
            )
            present(window)
            return
        }

        let controller = NSHostingController(rootView: SettingsView().environmentObject(store))
        let window = NSWindow(contentViewController: controller)
        window.title = "Cadence Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 620, height: 520))
        window.center()
        window.delegate = self
        self.window = window
        present(window)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
