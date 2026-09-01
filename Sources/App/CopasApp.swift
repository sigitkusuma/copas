import SwiftUI

/// Entry point.
///
/// The app is `LSUIElement` — no Dock icon, no main menu — so there is no
/// `WindowGroup` here. The clipboard board is an `NSPanel` managed by
/// `AppCoordinator`; the only SwiftUI scene is Settings, which macOS wires to
/// ⌘, and to the status-item menu for free.
@main
struct CopasApp: App {
    @NSApplicationDelegateAdaptor(AppCoordinator.self) private var coordinator

    var body: some Scene {
        Settings {
            SettingsScene()
        }
    }
}
