import AppKit
import Carbon.HIToolbox
import Foundation

/// Which shortcut fired. Carbon identifies hotkeys by a number, so each one
/// needs a stable id the shared handler can route on.
enum HotkeyID: UInt32, Sendable, CaseIterable {
    case showBoard = 1
    case captureToText = 2
}

/// Registers global keyboard shortcuts and routes them back to Swift.
///
/// Carbon's `RegisterEventHotKey` rather than an `NSEvent` global monitor,
/// because a monitor only observes: the keystroke still reaches whatever app is
/// frontmost. A registered hotkey is consumed, which is what a shortcut has to
/// do to be one.
@MainActor
final class HotkeyCenter {

    private var registrations: [HotkeyID: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?

    init() {}

    /// `isolated deinit`, so this can touch the main-actor state it owns. The
    /// alternative — an unisolated deinit reaching into it anyway — is a data
    /// race the compiler is right to reject.
    isolated deinit {
        unregisterAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    /// Claims a shortcut. Returns `false` when the system refuses it, which in
    /// practice means another running app already holds that combination — the
    /// exact situation two copies of this app installed at once produce, and the
    /// reason the second one looks broken rather than noisy.
    @discardableResult
    func register(
        _ id: HotkeyID,
        combination: KeyCombination,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> Bool {
        unregister(id)
        guard installHandlerIfNeeded() else { return false }

        HotkeyActions.shared.set(action, for: id.rawValue)

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combination.keyCode),
            combination.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: id.rawValue),
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            HotkeyActions.shared.set(nil, for: id.rawValue)
            Log.app.error("could not register \(combination.displayString, privacy: .public) — status \(status)")
            return false
        }

        registrations[id] = reference
        Log.app.info("registered \(combination.displayString, privacy: .public)")
        return true
    }

    func unregister(_ id: HotkeyID) {
        if let reference = registrations.removeValue(forKey: id) {
            UnregisterEventHotKey(reference)
        }
        HotkeyActions.shared.set(nil, for: id.rawValue)
    }

    func unregisterAll() {
        for id in registrations.keys {
            unregister(id)
        }
    }

    // MARK: - Carbon plumbing

    /// "CPAS". Carbon wants a four-character code to namespace hotkey ids.
    private static let signature = OSType(0x4350_4153)

    private func installHandlerIfNeeded() -> Bool {
        guard handlerRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var pressed = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressed
                )
                guard let action = HotkeyActions.shared.action(for: pressed.id) else {
                    return noErr
                }
                // Carbon calls this on the main thread, but the C function
                // pointer cannot carry that guarantee into Swift. Hopping is a
                // single run-loop turn — imperceptible for a keystroke, and it
                // cannot trap the way asserting the isolation could.
                Task { @MainActor in action() }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )

        guard status == noErr else {
            Log.app.error("could not install the hotkey handler — status \(status)")
            return false
        }
        return true
    }
}

/// The bridge between a C function pointer and Swift closures.
///
/// Carbon's handler is a bare function pointer with no captured context, so the
/// actions have to live somewhere reachable from it. A lock rather than actor
/// isolation because the callback cannot await.
private final class HotkeyActions: @unchecked Sendable {

    static let shared = HotkeyActions()

    private let lock = NSLock()
    private var actions: [UInt32: @MainActor @Sendable () -> Void] = [:]

    func set(_ action: (@MainActor @Sendable () -> Void)?, for id: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        actions[id] = action
    }

    func action(for id: UInt32) -> (@MainActor @Sendable () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return actions[id]
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        actions.removeAll()
    }
}
