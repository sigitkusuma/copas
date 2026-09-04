import SwiftUI

/// What the welcome window can ask the rest of the app to do.
///
/// Mirrors ``SettingsActions``: closures rather than a coordinator reference,
/// so the view can be previewed and tested without an app around it.
@MainActor
struct WelcomeActions {
    var requestAccessibilityTrust: () -> Void = {}
    var finish: () -> Void = {}
}

/// The first thing a new install sees: what the two shortcuts do, and the one
/// permission worth asking for up front.
///
/// Screen Recording is deliberately absent here — ``RegionCapture`` asks for it
/// lazily, the first time Capture to Text is actually used, and a welcome
/// screen that front-loaded every permission the app might ever need would
/// undercut that. Accessibility is different: it has exactly one grant to ask
/// for, the system shows its prompt at most once per install, and without it
/// the app's headline feature — press Return, have it paste — silently
/// degrades to "copied, paste it yourself".
struct WelcomeScene: View {

    var actions = WelcomeActions()

    @State private var isAccessibilityTrusted = Paster.isTrustedForAccessibility

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(systemName: "square.on.square.dashed")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.accent)

                VStack(spacing: 4) {
                    Text("Welcome to Copas")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Everything you copy, kept, searchable, and one keystroke away.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 22)
            .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 14) {
                ShortcutRow(
                    combination: .showBoard,
                    symbol: "square.stack",
                    title: "Open the board",
                    detail: "Everything you've copied, newest first. Type to search."
                )
                ShortcutRow(
                    combination: .captureToText,
                    symbol: "text.viewfinder",
                    title: "Capture to text",
                    detail: "Drag over a receipt, an error, a screenshot — the text lands on your clipboard."
                )

                ThemeSeparator()

                AccessibilityRow(
                    isTrusted: isAccessibilityTrusted,
                    request: {
                        actions.requestAccessibilityTrust()
                        isAccessibilityTrusted = Paster.isTrustedForAccessibility
                    }
                )

                Text("""
                    Copas lives in the menu bar from now on — look for the mark near \
                    the clock. Right-click it any time for Settings.
                    """)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            // A window that has gone to System Settings and back should not
            // still be showing a stale "not granted" state.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                isAccessibilityTrusted = Paster.isTrustedForAccessibility
            }

            ThemeSeparator()

            HStack {
                Spacer()
                Button("Get Started") { actions.finish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 420)
    }
}

private struct ShortcutRow: View {
    let combination: KeyCombination
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(combination.displayString)
                .font(.system(size: 12, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.field)
                )
        }
    }
}

private struct AccessibilityRow: View {
    let isTrusted: Bool
    let request: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.point.up.left")
                .font(.system(size: 15))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text("Paste for you")
                    .font(.system(size: 13, weight: .medium))
                Text("Accessibility lets Copas press ⌘V after you pick a clip. Without it, the clip is still copied — you paste by hand.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isTrusted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.green)
                    .fixedSize()
            } else {
                Button("Enable…", action: request)
                    .fixedSize()
            }
        }
    }
}

#Preview {
    WelcomeScene()
}
