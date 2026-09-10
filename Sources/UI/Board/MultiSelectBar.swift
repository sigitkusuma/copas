import AppKit
import SwiftUI

/// The detail pane view displayed when multiple clips are selected.
///
/// Gives users a visual overview of what is selected, lets them choose a delimiter,
/// and provides one-click / keyboard-driven merging onto the pasteboard.
struct MultiSelectDetail: View {

    @Bindable var model: BoardModel
    @State private var selectedDelimiter: MergeDelimiter = .doubleNewline
    @State private var copiedConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ThemeSeparator()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    delimiterPicker

                    clipsList

                    actions
                }
                .padding(Theme.detailPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)

            Text("\(model.selectedIDs.count) clips selected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            Button("Deselect") {
                model.clearSelection()
            }
            .font(.system(size: Theme.metaSize))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.detailPadding)
        .frame(height: 34)
        .background(Theme.canvasSubtle)
    }

    // MARK: - Delimiter Picker

    private var delimiterPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("JOIN WITH")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            HStack(spacing: 6) {
                ForEach(MergeDelimiter.allCases) { delimiter in
                    let isCurrent = selectedDelimiter == delimiter
                    Button {
                        selectedDelimiter = delimiter
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: delimiter.icon)
                                .font(.system(size: 10))
                            Text(delimiter.rawValue)
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isCurrent ? Theme.accent.opacity(0.12) : Theme.field)
                        .foregroundStyle(isCurrent ? Theme.accent : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            if isCurrent {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Selected Clips List

    private var clipsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ITEMS IN MERGE ORDER")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                ForEach(Array(model.selectedCards.enumerated()), id: \.element.id) { index, card in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 16, alignment: .trailing)

                        Text(card.listTitle)
                            .font(.system(size: 11, design: card.isMonospaced ? .monospaced : .default))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(.primary)

                        Spacer()

                        Button {
                            model.toggleSelection(for: card.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from selection")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.field.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                model.mergeSelected(delimiter: selectedDelimiter)
                copiedConfirmation = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copiedConfirmation = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                    Text(copiedConfirmation ? "Merged & Copied!" : "Merge & Copy (⌘M)")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Theme.accent)
                .foregroundStyle(Theme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                model.deleteSelected()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Delete (\(model.selectedIDs.count))")
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.destructive)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }
}
