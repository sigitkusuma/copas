import AppKit
import SwiftUI

/// An AppKit-backed text editor view that integrates with Apple Intelligence Writing Tools
/// on macOS 15+ (Sequoia) while providing robust text editing and search highlighting.
struct ClipTextView: NSViewRepresentable {

    @Binding var text: String
    let isMonospaced: Bool
    let terms: [String]
    var onTextChange: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.minSize = NSSize(width: 0.0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.delegate = context.coordinator

        // Text appearance
        let font: NSFont
        if isMonospaced {
            font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        } else {
            font = NSFont.systemFont(ofSize: 13)
        }
        textView.font = font
        textView.textColor = .textColor

        // Apple Intelligence Writing Tools integration on macOS 15+
        if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .complete
        }

        textView.string = text
        context.coordinator.textView = textView
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update textView.string if it differs externally, avoiding cursor reset
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            // Restore selection if still within range
            if selectedRange.location + selectedRange.length <= text.count {
                textView.setSelectedRange(selectedRange)
            }
        }

        // Update font if monospace setting changed
        let expectedFont: NSFont = isMonospaced
            ? .monospacedSystemFont(ofSize: 13, weight: .regular)
            : .systemFont(ofSize: 13)
        if textView.font != expectedFont {
            textView.font = expectedFont
        }
    }

    // MARK: - Programmatic Writing Tools Trigger

    /// Requests the system to open the Apple Intelligence Writing Tools palette.
    static func triggerWritingTools() {
        let selector = NSSelectorFromString("showWritingTools:")
        NSApp.sendAction(selector, to: nil, from: nil)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ClipTextView
        weak var textView: NSTextView?

        init(_ parent: ClipTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            if parent.text != newText {
                parent.text = newText
                parent.onTextChange?(newText)
            }
        }
    }
}
