import AppKit
import SwiftUI

/// The action toolbar inserted between the header and content in ``ClipDetail``.
///
/// Two zones:
/// 1. Quick-action buttons — contextual to what the clip *is* (URL → Open,
///    email → Compose, etc.)
/// 2. A Transforms menu — the full list of text mutations the user can apply
///    and copy without touching the original clip.
///
/// Only shown for text clips. Images carry no actions here.
struct ClipActionBar: View {

    let text: String
    let card: ClipCardModel
    /// Called when the user picks a transform. The coordinator writes the
    /// transformed text to the pasteboard.
    let onTransform: (TextTransform) -> Void
    /// Called when a quick action wants to dismiss the board (e.g. Open URL).
    let onDismiss: () -> Void

    @State private var copiedActionLabel: String? = nil

    private var contentType: ClipContentType { ClipContentType.classify(text) }

    var body: some View {
        HStack(spacing: 2) {
            quickActions
            Spacer(minLength: 6)
            transformsButton
        }
        .padding(.horizontal, Theme.detailPadding)
        .frame(height: Theme.hintBarHeight)
        .background(Theme.canvasSubtle)
        .animation(Theme.Motion.contentIn, value: copiedActionLabel)
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActions: some View {
        switch contentType {
        case .url(let url):
            actionButton("Open", icon: "arrow.up.right.square") {
                NSWorkspace.shared.open(url)
                onDismiss()
            }
            actionButton("Copy as Markdown", icon: "link") {
                let md = "[\(url.host ?? url.absoluteString)](\(url.absoluteString))"
                writeToClipboard(md, label: "Copied")
            }

        case .email(let address):
            actionButton("Compose", icon: "envelope") {
                if let url = URL(string: "mailto:\(address)") {
                    NSWorkspace.shared.open(url)
                }
            }

        case .phone(let number):
            actionButton("FaceTime", icon: "phone") {
                let digits = number.filter(\.isNumber)
                if let url = URL(string: "facetime:\(digits)") {
                    NSWorkspace.shared.open(url)
                }
            }

        case .hexColor(let hex):
            colorSwatch(hex: hex)
            actionButton("Copy as RGB", icon: "paintpalette") {
                writeToClipboard(hexToRGB(hex), label: "Copied")
            }

        case .filePath(let path):
            actionButton("Reveal in Finder", icon: "folder") {
                let expanded = (path as NSString).expandingTildeInPath
                NSWorkspace.shared.selectFile(expanded, inFileViewerRootedAtPath: "")
            }

        case .uuid(let uuid):
            actionButton("Copy without Dashes", icon: "minus") {
                writeToClipboard(uuid.replacingOccurrences(of: "-", with: ""), label: "Copied")
            }

        case .json:
            EmptyView()   // JSON quick actions live in the transforms menu

        case .plain:
            EmptyView()
        }

        // Confirmation badge — fades in when an action copies to clipboard.
        if let label = copiedActionLabel {
            Text(label)
                .font(.system(size: Theme.metaSize, weight: .medium))
                .foregroundStyle(Theme.accent)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    // MARK: - Transforms Menu

    private var transformsButton: some View {
        Menu {
            let transforms = TextTransform.available(for: text)
            let apt = transforms.prefix(while: { $0.isApt(for: text) })

            if !apt.isEmpty {
                Section("Suggested") {
                    ForEach(apt) { transform in
                        Button {
                            onTransform(transform)
                            flash("Transformed & Copied")
                        } label: {
                            Label(transform.label, systemImage: transform.systemImage)
                        }
                    }
                }
                Divider()
            }

            Section("All Transforms") {
                ForEach(transforms.dropFirst(apt.count)) { transform in
                    Button {
                        onTransform(transform)
                        flash("Transformed & Copied")
                    } label: {
                        Label(transform.label, systemImage: transform.systemImage)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 11, weight: .medium))
                Text("Transform")
                    .font(.system(size: Theme.metaSize, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Theme.chipRadius + 2)
                    .fill(Theme.field)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Transform and copy this clip  ⌘T")
    }

    // MARK: - Helpers

    @ViewBuilder
    private func actionButton(
        _ label: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: Theme.metaSize, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Theme.chipRadius + 2)
                    .fill(Theme.field)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func colorSwatch(hex: String) -> some View {
        if let color = color(from: hex) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 16, height: 16)
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Theme.ruleStrong, lineWidth: 1)
                }
        }
    }

    private func writeToClipboard(_ string: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        flash(label)
    }

    private func flash(_ label: String) {
        copiedActionLabel = label
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copiedActionLabel = nil
        }
    }

    // MARK: - Color conversion

    private func color(from hex: String) -> Color? {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let expanded: String
        switch h.count {
        case 3:
            expanded = h.map { "\($0)\($0)" }.joined()
        case 6, 8:
            expanded = h
        default:
            return nil
        }
        guard let value = UInt64(expanded.prefix(6), radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }

    private func hexToRGB(_ hex: String) -> String {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let expanded: String
        switch h.count {
        case 3: expanded = h.map { "\($0)\($0)" }.joined()
        case 6, 8: expanded = h
        default: return hex
        }
        guard let value = UInt64(expanded.prefix(6), radix: 16) else { return hex }
        let r = (value >> 16) & 0xFF
        let g = (value >> 8) & 0xFF
        let b = value & 0xFF
        return "rgb(\(r), \(g), \(b))"
    }
}
