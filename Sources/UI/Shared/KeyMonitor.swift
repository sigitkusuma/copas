import AppKit
import SwiftUI

/// Routes key presses to a handler for as long as the view is on screen.
///
/// A local `NSEvent` monitor rather than `@FocusState` and `onKeyPress`. The
/// board is a non-activating panel, where SwiftUI's focus machinery is
/// unreliable — a card can look focused and still not receive a keystroke — and
/// where the board needs to claim keys like Space and ⌫ outright rather than
/// negotiate for them.
///
/// Returning `true` from the handler swallows the event; `false` lets it through
/// to whatever would have had it, which is what keeps ⌘Q and ⌘W working.
struct KeyMonitor: NSViewRepresentable {

    let handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install(handler)
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handler = handler
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        // SwiftUI tears views down on the main thread; the isolation is real,
        // it simply cannot be spelled on a static requirement.
        MainActor.assumeIsolated { coordinator.remove() }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        var handler: ((NSEvent) -> Bool)?
        private var monitor: Any?

        func install(_ handler: @escaping (NSEvent) -> Bool) {
            self.handler = handler
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let handled = self?.handler?(event), handled else { return event }
                return nil
            }
        }

        func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            handler = nil
        }

        isolated deinit {
            remove()
        }
    }
}
