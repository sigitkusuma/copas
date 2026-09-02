import SwiftUI

/// The label between one day's clips and the next.
///
/// Pinned by the lazy stack, so the day you have scrolled into stays named at
/// the top of the list.
struct DayHeader: View {

    let label: String

    var body: some View {
        Text(label.uppercased())
            .font(.system(size: Theme.metaSize, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, Theme.rowPadding + 2)
            .frame(
                maxWidth: .infinity,
                minHeight: Theme.sectionHeaderHeight,
                alignment: .leading
            )
            .background(
                // Opaque, or rows scroll visibly underneath the pinned header.
                Rectangle()
                    .fill(Theme.canvas)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.rule).frame(height: 1)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isHeader)
    }
}
