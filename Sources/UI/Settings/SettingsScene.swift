import SwiftUI

/// Settings. Filled in properly in the shell phase; for now it exists so the
/// Settings scene and the ⌘, path are wired and testable from the start.
struct SettingsScene: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("Copas")
                .font(.system(size: 15, weight: .semibold))
            Text(version)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("A clipboard manager for macOS.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 380, height: 160)
        .background(Theme.canvas)
    }
}
