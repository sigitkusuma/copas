import SwiftUI
import AppKit

/// Copas's visual identity, in one place.
///
/// Swiss/minimal: paper-white surfaces, near-black text, one accent colour,
/// square geometry, and hairline rules instead of boxes. Hierarchy comes from
/// whitespace and type weight rather than from fills, borders, and shadows.
enum Theme {

    // MARK: - Accent
    //
    // Exactly one. Everything else is monochrome.

    static let accent = Color(red: 0.329, green: 0.341, blue: 0.941)   // #5457F0

    // MARK: - Surfaces

    /// The board itself. Paper in light mode, near-black in dark — not grey,
    /// and not translucent: content should read as printed on a page.
    static let canvas = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.07, alpha: 1.0)
            : NSColor.white
    })

    /// Search header and footer. A whisper away from the canvas.
    static let canvasSubtle = Color.primary.opacity(0.025)

    /// Fields, chips, and card grounds.
    static let field = Color.primary.opacity(0.05)

    // MARK: - Selection

    static let selection = accent.opacity(0.07)
    static let selectionSecondary = accent.opacity(0.04)
    static let hover = Color.primary.opacity(0.035)

    // MARK: - Rules

    static let rule = Color.primary.opacity(0.09)
    static let ruleStrong = Color.primary.opacity(0.14)

    // MARK: - Semantic

    static let bookmark = Color(red: 0.85, green: 0.62, blue: 0.13)
    static let destructive = Color(red: 0.83, green: 0.24, blue: 0.24)

    // MARK: - Geometry
    //
    // The board is a horizontal strip of cards, so unlike the full-bleed rows
    // of the list design these are discrete objects and do carry a radius —
    // just a small one. Everything else stays square.

    static let cardWidth: CGFloat = 264
    static let cardHeight: CGFloat = 328
    static let cardGap: CGFloat = 12
    static let cardRadius: CGFloat = 6
    static let cardPadding: CGFloat = 14

    /// Thumbnails are generated at 2x the card width so they stay crisp on
    /// Retina without decoding the full image.
    static let thumbnailMaxPixel: CGFloat = cardWidth * 2

    /// The pinned day rail down the leading edge of the strip.
    static let dayRailWidth: CGFloat = 24

    /// The row of key hints along the bottom edge.
    static let hintBarHeight: CGFloat = 26

    /// Derived, not chosen. A height picked independently of the card it holds
    /// drifts the moment either changes, and the slack shows up as a band of
    /// empty panel under the cards.
    static let boardHeight: CGFloat = gutter + cardHeight + 12 + hintBarHeight
    static let controlRadius: CGFloat = 0
    static let chipRadius: CGFloat = 2
    static let focusRingWidth: CGFloat = 2

    // MARK: - Rhythm

    static let gutter: CGFloat = 18

    // MARK: - Type

    static let titleSize: CGFloat = 13
    static let metaSize: CGFloat = 10.5
}

/// A hairline rule. Replaces `Divider()`, which renders heavier and inherits
/// system inset behaviour that breaks the full-bleed grid.
struct ThemeSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Theme.rule)
            .frame(height: 1)
    }
}

// MARK: - Motion
//
// The same restraint as the palette: a small fixed vocabulary, used everywhere,
// rather than a duration invented at each call site. Motion here exists to keep
// a change legible — where a row went, that a press registered — never to
// decorate. Anything that cannot justify itself that way stays instant.

extension Theme {
    enum Motion {
        /// Reduce Motion is a positional concern, not a fade concern: Apple's
        /// guidance is to drop movement, not cross-fades. So `hover` and `press`
        /// are unchanged when it is on, and only `reorder` loses its spring.
        private static var reduced: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        /// Row and control hover tints. Short enough to feel attached to the cursor.
        static let hover = Animation.easeOut(duration: 0.12)

        /// Button press-down and release.
        static let press = Animation.easeOut(duration: 0.10)

        /// The selection tint and accent bar moving between rows. Deliberately
        /// shorter than `hover`: held arrow keys repeat faster than a longer
        /// fade can finish, and each row fades independently, so anything
        /// slower leaves a smear of half-lit rows behind the cursor.
        static let selection = Animation.easeOut(duration: 0.10)

        /// Rows changing position — pinning, and items arriving or leaving.
        /// The one place a spring is warranted: the row is travelling a real
        /// distance and the overshoot is what the eye follows.
        static var reorder: Animation {
            reduced
                ? .easeInOut(duration: 0.2)
                : .spring(response: 0.32, dampingFraction: 0.86)
        }

        /// Async content resolving into place — an image preview finishing its load.
        static let contentIn = Animation.easeOut(duration: 0.18)

        /// A panel or inline disclosure revealing and dismissing — the delete
        /// confirmation, and the strips that insert themselves into the layout.
        static let panel = Animation.easeOut(duration: 0.16)

        /// Above this many rows changing at once, animating costs more than it
        /// communicates: clearing the whole history should not spring 500 rows
        /// through a LazyVStack. Bulk changes apply instantly.
        static let bulkChangeThreshold = 25
    }
}

// MARK: - Button styles
//
// `.buttonStyle(.plain)` strips AppKit's press highlight and puts nothing back,
// which left every control in the app silent on click. These restore the
// acknowledgement while keeping the flat, borderless look.

// A ButtonStyle is not itself a View, so `@State` and `@Environment` declared on
// one have no SwiftUI storage backing them — hover would not survive a redraw.
// Both styles therefore keep their state in a nested view that `makeBody`
// returns, which is a real view and does get storage.

/// The primary action — the Paste button. Darkens and settles slightly on press.
struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .fill(Theme.accent)
                        .brightness(configuration.isPressed ? -0.10 : (isHovered ? 0.06 : 0))
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(Theme.Motion.press, value: configuration.isPressed)
                .animation(Theme.Motion.hover, value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

/// Press feedback and nothing else. For buttons whose label already carries its
/// own fill — the confirmation pair, tag chips — where a style that imposed a
/// background would fight what is already there.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1.0) : 0.4)
                .animation(Theme.Motion.press, value: configuration.isPressed)
        }
    }
}

/// Borderless icon buttons — the detail-pane toolbar. A hover plate appears
/// behind the glyph so the hit target is discoverable before it is clicked.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.hover)
                        .opacity(isEnabled && (isHovered || configuration.isPressed) ? 1 : 0)
                )
                .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1.0) : 0.4)
                .animation(Theme.Motion.press, value: configuration.isPressed)
                .animation(Theme.Motion.hover, value: isHovered)
                // A disabled button should not advertise a hover it will not honour.
                .onHover { isHovered = isEnabled && $0 }
        }
    }
}

/// A spinner that appears only if the work outlasts `delay`. A cached preview
/// resolves well inside that window, so the fast path shows nothing at all
/// rather than strobing a spinner for a frame or two on every arrow keypress.
///
/// The `.task` is torn down when the view is removed, so a load that finishes
/// first never flips `visible`.
struct DelayedProgressView: View {
    var delay: Double = 0.18

    @State private var visible = false

    var body: some View {
        ProgressView()
            .opacity(visible ? 1 : 0)
            .animation(Theme.Motion.contentIn, value: visible)
            .task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                visible = true
            }
    }
}
