import AppKit

/// The menu-bar presence: the only always-visible part of the app.
///
/// Left-click toggles the board, right-click opens the menu. Keeping those on
/// separate buttons rather than always showing a menu is what makes the status
/// item a one-click affordance rather than a two-step one.
@MainActor
final class StatusItemController {

    /// What the menu can do. A struct rather than seven initialiser arguments,
    /// so adding an item does not mean threading another closure through.
    struct Actions {
        var toggleBoard: () -> Void = {}
        var captureToText: () -> Void = {}
        var togglePause: () -> Void = {}
        var isPaused: () -> Bool = { false }
        var isCaptureToTextEnabled: () -> Bool = { true }
        var shortcuts: () -> (board: KeyCombination, capture: KeyCombination) = {
            (.showBoard, .captureToText)
        }
        var checkForUpdates: () -> Void = {}
        var openSettings: () -> Void = {}
        var quit: () -> Void = {}
    }

    private let statusItem: NSStatusItem
    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
    }

    /// Dims the icon while capture is paused, so the state is visible without
    /// opening anything. A paused clipboard manager that looks exactly like a
    /// running one is a bug report waiting to happen.
    func refresh() {
        statusItem.button?.appearsDisabled = actions.isPaused()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "square.on.square.dashed",
            accessibilityDescription: "Copas"
        )
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(buttonClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func buttonClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            presentMenu()
        } else {
            actions.toggleBoard()
        }
    }

    private func presentMenu() {
        let menu = NSMenu()
        let shortcuts = actions.shortcuts()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let header = NSMenuItem(title: "Copas \(version)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(item(
            "Show Clipboard",
            #selector(menuToggleBoard),
            shortcut: shortcuts.board
        ))

        let capture = item(
            "Capture to Text",
            #selector(menuCaptureToText),
            shortcut: shortcuts.capture
        )
        capture.isEnabled = actions.isCaptureToTextEnabled()
        menu.addItem(capture)

        menu.addItem(.separator())
        menu.addItem(item(
            actions.isPaused() ? "Resume Capture" : "Pause Capture",
            #selector(menuTogglePause)
        ))

        menu.addItem(.separator())
        menu.addItem(item("Check for Updates…", #selector(menuCheckForUpdates)))
        menu.addItem(item("Settings…", #selector(menuOpenSettings), key: ","))
        menu.addItem(item("Quit Copas", #selector(menuQuit), key: "q"))

        // Attaching the menu for one click and clearing it immediately keeps
        // left-click free for the board; a permanently assigned menu would
        // swallow it.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    /// Shows the real shortcut beside the item, so the menu teaches the keyboard
    /// rather than replacing it.
    private func item(_ title: String, _ action: Selector, shortcut: KeyCombination) -> NSMenuItem {
        let menuItem = item(title, action)
        menuItem.keyEquivalent = KeyCombination.keyName(for: shortcut.keyCode).lowercased()

        var mask: NSEvent.ModifierFlags = []
        if shortcut.modifiers.contains(.command) { mask.insert(.command) }
        if shortcut.modifiers.contains(.shift) { mask.insert(.shift) }
        if shortcut.modifiers.contains(.option) { mask.insert(.option) }
        if shortcut.modifiers.contains(.control) { mask.insert(.control) }
        menuItem.keyEquivalentModifierMask = mask

        return menuItem
    }

    @objc private func menuToggleBoard() { actions.toggleBoard() }
    @objc private func menuCaptureToText() { actions.captureToText() }
    @objc private func menuTogglePause() { actions.togglePause(); refresh() }
    @objc private func menuCheckForUpdates() { actions.checkForUpdates() }
    @objc private func menuOpenSettings() { actions.openSettings() }
    @objc private func menuQuit() { actions.quit() }
}
