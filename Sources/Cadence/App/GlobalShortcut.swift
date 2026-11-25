import AppKit
import Carbon
import Combine

struct PanelShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyName: String

    init?(event: NSEvent) {
        let flags = event.modifierFlags
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        guard let key = event.characters(byApplyingModifiers: []), key.count == 1,
            let scalar = key.unicodeScalars.first,
            !CharacterSet.controlCharacters.contains(scalar),
            !(0xF700...0xF8FF).contains(scalar.value)
        else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = mask
        keyName = key == " " ? "Espaço" : key.uppercased()
    }

    var label: String {
        let symbols = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
        return symbols.filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + keyName
    }
}

@MainActor
final class GlobalShortcut: ObservableObject {
    static let shared = GlobalShortcut()

    @Published private(set) var shortcut: PanelShortcut?
    @Published private(set) var isRecording = false
    @Published private(set) var message: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private let preference = "openPanelShortcut"
    private let hotKeyID = EventHotKeyID(signature: 0x4344_4E43, id: 1)  // CDNC
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var monitor: Any?
    private var openPanel: (() -> Void)?

    func start(openPanel: @escaping () -> Void) {
        self.openPanel = openPanel
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr else { return status }
                return MainActor.assumeIsolated {
                    let manager = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
                    guard id.signature == manager.hotKeyID.signature, id.id == manager.hotKeyID.id else {
                        return OSStatus(eventNotHandledErr)
                    }
                    if manager.isRecording {
                        manager.stopRecording()
                    } else {
                        manager.openPanel?()
                    }
                    return noErr
                }
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)

        if let data = defaults.data(forKey: preference),
            let saved = try? JSONDecoder().decode(PanelShortcut.self, from: data)
        {
            shortcut = saved
            register(saved)
        }
    }

    deinit {
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
    }

    func startRecording() {
        guard monitor == nil, let window = NSApp.keyWindow else { return }
        isRecording = true
        message = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window, window.isKeyWindow, event.window === window else { return event }
            self.record(event)
            return nil
        }
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == kVK_Escape {
            stopRecording()
            return
        }
        guard let candidate = PanelShortcut(event: event) else {
            message = "Combine ⌘, ⌥ ou ⌃ com uma letra, número, símbolo ou espaço."
            return
        }
        save(candidate)
    }

    func save(_ candidate: PanelShortcut) {
        guard register(candidate) else { return }
        shortcut = candidate
        defaults.set(try? JSONEncoder().encode(candidate), forKey: preference)
        stopRecording()
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    func remove() {
        stopRecording()
        if let registration { UnregisterEventHotKey(registration) }
        registration = nil
        shortcut = nil
        message = nil
        defaults.removeObject(forKey: preference)
    }

    @discardableResult
    private func register(_ candidate: PanelShortcut) -> Bool {
        var replacement: EventHotKeyRef?
        guard handler != nil,
            RegisterEventHotKey(
                candidate.keyCode, candidate.modifiers, hotKeyID,
                GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive),
                &replacement) == noErr
        else {
            message = "Atalho indisponível. Escolha outra combinação."
            return false
        }
        if let registration { UnregisterEventHotKey(registration) }
        registration = replacement
        message = nil
        return true
    }
}
