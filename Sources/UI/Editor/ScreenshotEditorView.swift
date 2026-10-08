import SwiftUI

/// The editor: tools along the top, the picture in the middle, and the way out
/// along the bottom.
struct ScreenshotEditorView: View {

    let model: ScreenshotEditorModel
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var showsResize = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            EditorCanvas(
                model: model,
                document: model.document,
                tool: model.tool,
                selectedID: model.selectedID,
                color: model.color,
                textPoints: model.textPoints
            )
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 360)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(EditorTool.allCases, id: \.self) { tool in
                    toolButton(tool)
                }
            }

            Divider().frame(height: 18)

            HStack(spacing: 6) {
                ForEach(Array(AnnotationColor.palette.enumerated()), id: \.offset) { _, color in
                    swatch(color)
                }
            }

            Divider().frame(height: 18)

            weightPicker

            Spacer(minLength: 0)

            Button(action: model.undo) { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo (⌘Z)")
            Button(action: model.redo) { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("Redo (⇧⌘Z)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toolButton(_ tool: EditorTool) -> some View {
        let isActive = model.tool == tool
        return Button {
            model.tool = tool
        } label: {
            Image(systemName: tool.symbol)
                .font(.system(size: 14))
                .frame(width: 30, height: 26)
                .background(isActive ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(isActive ? Theme.accent : Color.secondary)
        }
        .help(tool.help)
        .accessibilityLabel(tool.title)
    }

    private func swatch(_ color: AnnotationColor) -> some View {
        let isChosen = model.color == color
        return Button {
            model.choose(color)
        } label: {
            Circle()
                .fill(Color(nsColor: color.nsColor))
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                .padding(2)
                .overlay(Circle().strokeBorder(isChosen ? Theme.accent : Color.clear, lineWidth: 1.5))
        }
        .accessibilityLabel("Colour")
    }

    /// Line weight for shapes, size for text; neither means anything for a
    /// highlight, a blur or a crop, so nothing is shown for those.
    @ViewBuilder
    private var weightPicker: some View {
        switch model.tool {
        case .rectangle, .ellipse:
            Picker("Line", selection: Bindable(model).strokePoints) {
                Text("Thin").tag(ScreenshotEditorModel.strokeChoices[0])
                Text("Medium").tag(ScreenshotEditorModel.strokeChoices[1])
                Text("Thick").tag(ScreenshotEditorModel.strokeChoices[2])
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
        case .text:
            Picker("Size", selection: Bindable(model).textPoints) {
                Text("Small").tag(ScreenshotEditorModel.textChoices[0])
                Text("Medium").tag(ScreenshotEditorModel.textChoices[1])
                Text("Large").tag(ScreenshotEditorModel.textChoices[2])
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
        case .select, .highlight, .blur, .crop:
            EmptyView()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            let size = model.document.outputSize
            Text("\(Int(size.width)) × \(Int(size.height)) px")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)

            Button("Resize…") { showsResize = true }
                .popover(isPresented: $showsResize, arrowEdge: .top) {
                    ResizePopover(model: model)
                }

            if model.document.isCropped {
                Button("Reset Crop") { model.resetCrop() }
            }

            Spacer(minLength: 0)

            Text("Return copies  ·  Esc discards")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button("Done", action: onDone)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Resize by preset, or by typing one dimension; the other follows.
private struct ResizePopover: View {

    let model: ScreenshotEditorModel

    @State private var width = ""
    @State private var height = ""

    private static let presets: [(label: String, scale: CGFloat)] = [
        ("100%", 1), ("75%", 0.75), ("50%", 0.5), ("25%", 0.25),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.label) { preset in
                    Button(preset.label) {
                        model.setOutputScale(preset.scale)
                        sync()
                    }
                }
            }

            HStack(spacing: 8) {
                field("W", text: $width) { value in model.setOutputWidth(value) }
                Text("×").foregroundStyle(.secondary)
                field("H", text: $height) { value in model.setOutputHeight(value) }
                Text("px").foregroundStyle(.secondary)
            }

            Text("Aspect ratio is kept.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .onAppear(perform: sync)
    }

    private func field(_ label: String, text: Binding<String>, apply: @escaping (CGFloat) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            TextField("", text: text)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
                .onSubmit {
                    if let value = Double(text.wrappedValue), value >= 1 {
                        apply(CGFloat(value))
                    }
                    sync()
                }
        }
    }

    private func sync() {
        let size = model.document.outputSize
        width = String(Int(size.width))
        height = String(Int(size.height))
    }
}
