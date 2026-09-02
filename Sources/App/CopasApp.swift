import SwiftUI

/// Entry point.
///
/// The app is `LSUIElement` — no Dock icon, no main menu — so there is no
/// `WindowGroup` here. Every window it shows is an AppKit one built by
/// `AppCoordinator`: the clipboard board is an `NSPanel`, and Settings is an
/// `NSWindow`.
@main
struct CopasApp: App {
    @NSApplicationDelegateAdaptor(AppCoordinator.self) private var coordinator

    var body: some Scene {
        // `App` has to declare a scene, and this one is deliberately empty.
        // SwiftUI never presents a `Settings` scene for an app whose activation
        // policy is `.accessory`, and the private selector that asks it to
        // reports success regardless — so putting the real settings here would
        // be a decoy that silently does nothing. See `SettingsWindowController`.
        Settings { EmptyView() }
    }
}
