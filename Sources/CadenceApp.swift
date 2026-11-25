import AppKit
import Combine
import SwiftUI

@main
@MainActor
enum CadenceApp {
    static func main() {
        let app = NSApplication.shared
        let controller = MenuBarController()
        app.delegate = controller
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(controller) { app.run() }
    }
}

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
    private lazy var store = CadenceStore()
    private let popover = NSPopover()
    private var item: NSStatusItem?
    private var titleUpdates: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The account editor and search field use the standard responder-chain commands.
        let mainMenu = NSMenu()
        let editMenu = NSMenu(title: "Editar")
        mainMenu.addItem(withTitle: "Editar", action: nil, keyEquivalent: "").submenu = editMenu
        for (title, action, key) in [
            ("Desfazer", Selector(("undo:")), "z"), ("Refazer", Selector(("redo:")), "Z"),
            ("Recortar", #selector(NSText.cut(_:)), "x"), ("Copiar", #selector(NSText.copy(_:)), "c"),
            ("Colar", #selector(NSText.paste(_:)), "v"), ("Selecionar tudo", #selector(NSText.selectAll(_:)), "a"),
        ] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        NSApp.mainMenu = mainMenu

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        let button = item.button
        button?.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "Cadence")
        button?.target = self
        button?.action = #selector(togglePanel)
        titleUpdates = store.$events.sink { [weak self] _ in
            DispatchQueue.main.async { button?.setAccessibilityLabel(self?.store.menuBarTitle) }
        }

        popover.behavior = .transient
        let content = NSHostingController(
            rootView: ContentView { [weak self] in
                guard let self else { return }
                self.popover.performClose(nil)
                SettingsWindowController.shared.show(store: self.store)
            }.environmentObject(store))
        popover.contentViewController = content
        // AppKit positions the first presentation using the size available before show().
        popover.contentSize = content.view.fittingSize
        if CommandLine.arguments.contains("--check-panel") {
            Task { await checkPanel() }
        } else {
            GlobalShortcut.shared.start { [weak self] in self?.showPanel() }
        }
    }

    /// Run in a separate process with an isolated cache before installing the app.
    private func checkPanel() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        item?.button?.performClick(nil)
        for opening in 1...2 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard popover.isShown, let view = popover.contentViewController?.view,
                let window = view.window, let screen = item?.button?.window?.screen,
                !view.bounds.isEmpty,
                screen.visibleFrame.contains(window.convertToScreen(view.convert(view.bounds, to: nil)))
            else {
                print("Panel content is outside the visible screen on opening \(opening).")
                exit(1)
            }
            popover.close()
            if opening == 1 {
                try? await Task.sleep(nanoseconds: 300_000_000)
                showPanel()
            }
        }
        print("Panel fits the visible screen on both openings.")
        exit(0)
    }

    @objc private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = item?.button else { return }
        store.syncIfStale()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
