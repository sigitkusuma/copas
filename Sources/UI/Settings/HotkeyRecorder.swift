import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A button that listens for the next shortcut you press.
struct HotkeyRecorder: View {

    @Binding var combination: KeyCombination
    var isEnabled = true

    @State private var isRecording = false
    @State private var complaint: String?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording.toggle()
                complaint = nil
            } label: {
                Text(isRecording ? "Press a shortcut…" : combination.displayString)
                    .font(.system(size: 12, weight: .medium))
                    .monospaced()
                    .frame(minWidth: 110)
                    .contentShape(Rectangle())
            }
            .disabled(!isEnabled)

            if let complaint {
                Text(complaint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if isRecording {
                Text("Escape to cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .background {
            if isRecording {
                KeyMonitor(handler: record)
            }
        }
        .onChange(of: isEnabled) {
            if !isEnabled { isRecording = false }
        }
    }

    private func record(_ event: NSEvent) -> Bool {
        if Int(event.keyCode) == kVK_Escape {
            isRecording = false
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: KeyCombination.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }

        // A global shortcut with no modifier — or only Shift — swallows that key
        // everywhere on the system. Binding one would make the machine feel
        // broken in a way that is genuinely hard to trace back to here.
        guard !modifiers.intersection([.command, .option, .control]).isEmpty else {
            complaint = "Needs ⌘, ⌥ or ⌃"
            return true
        }

        combination = KeyCombination(keyCode: event.keyCode, modifiers: modifiers)
        isRecording = false
        complaint = nil
        return true
    }
}
