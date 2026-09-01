import AppKit

/// The menu-bar presence: the only always-visible part of the app.
///
/// Left-click toggles the board, right-click opens the menu. Keeping those on
/// separate buttons rather than always showing a menu is what makes the status
/// item a one-click affordance rather than a two-step one.
@MainActor
final class StatusItemController {

    private let statusItem: NSStatusItem
    private let onToggleBoard: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    init(
        onToggleBoard: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onToggleBoard = onToggleBoard
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
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
            onToggleBoard()
        }
    }

    private func presentMenu() {
        let menu = NSMenu()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let header = NSMenuItem(title: "Copas \(version)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(item("Show Clipboard", #selector(menuToggleBoard)))
        menu.addItem(item("Settings…", #selector(menuOpenSettings), key: ","))
        menu.addItem(.separator())
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

    @objc private func menuToggleBoard() { onToggleBoard() }
    @objc private func menuOpenSettings() { onOpenSettings() }
    @objc private func menuQuit() { onQuit() }
}
