import SwiftUI

/// The rail between one day's clips and the next.
///
/// Vertical, because the strip runs horizontally and a header across the top
/// would cost the cards a third of their height. Pinned by the lazy stack, so
/// the day you are scrolled into stays named at the leading edge.
struct DayHeader: View {

    let label: String

    var body: some View {
        Text(label.uppercased())
            .font(.system(size: Theme.metaSize, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(.secondary)
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .frame(width: 24, height: Theme.cardHeight)
            .background(
                // Opaque, or cards scroll visibly underneath the pinned rail.
                Rectangle()
                    .fill(Theme.canvas)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Theme.rule).frame(width: 1)
                    }
            )
    }
}
