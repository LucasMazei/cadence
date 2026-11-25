import AppKit
import Carbon
import Foundation
import Testing

@testable import Cadence

@Test func backendCacheContract() throws {
    let fixture = try #require(Bundle.module.url(forResource: "task", withExtension: "json", subdirectory: "Fixtures"))
    let task = try JSONDecoder().decode(CadenceTask.self, from: Data(contentsOf: fixture))
    #expect(task.id == "work:t")
    #expect(task.parsedDueDate.map(DateFormatter.googleTaskDay.string(from:)) == "2026-01-01")
    #expect(!task.isCompleted)
}

@Test func linksFromCache() {
    #expect(CadenceStore.webURL("https://example.org/event")?.host == "example.org")
    #expect(CadenceStore.webURL("file:///tmp/example") == nil)
    #expect(CadenceStore.webURL("custom:action") == nil)
    #expect(CadenceStore.webURL("https://example.org@other.example") == nil)
}

@MainActor @Test func shortcutConflictKeepsSavedBinding() throws {
    _ = NSApplication.shared
    let suite = "cadence-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    func shortcut(_ code: Int, _ name: String) throws -> PanelShortcut {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: [.option, .shift, .control, .command], timestamp: 0, windowNumber: 0,
                context: nil, characters: name, charactersIgnoringModifiers: name, isARepeat: false,
                keyCode: UInt16(code)))
        return try #require(PanelShortcut(event: event))
    }
    let first = try shortcut(kVK_ANSI_M, "m")
    let occupied = try shortcut(kVK_ANSI_N, "n")
    var reservation: EventHotKeyRef?
    try #require(
        RegisterEventHotKey(
            occupied.keyCode, occupied.modifiers, EventHotKeyID(signature: 1234, id: 1),
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reservation) == noErr)
    defer { UnregisterEventHotKey(reservation) }
    do {
        let manager = GlobalShortcut(defaults: defaults)
        manager.start {}
        manager.save(first)
        try #require(manager.shortcut == first)
        manager.save(occupied)
        #expect(manager.message != nil)
        #expect(manager.shortcut == first)
    }
    let restored = GlobalShortcut(defaults: defaults)
    restored.start {}
    #expect(restored.shortcut == first)
    #expect(restored.message == nil)
    restored.remove()
}
