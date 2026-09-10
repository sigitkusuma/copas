import SwiftUI

/// A horizontal bar of filter pills positioned directly under the search bar.
///
/// Gives users one-tap access to common content types (Links, Code, Images, Colors, Pinned)
/// without having to type filter syntax.
struct FilterBar: View {

    @Bindable var model: BoardModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SmartFilter.allCases) { filter in
                    pill(filter)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 5)
        }
        .frame(height: 32)
        .background(Theme.canvasSubtle)
    }

    private func pill(_ filter: SmartFilter) -> some View {
        let isSelected = model.activeFilter == filter
        return Button {
            if isSelected && filter != .all {
                model.activeFilter = .all
            } else {
                model.activeFilter = filter
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: filter.icon)
                    .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(iconColor(for: filter, isSelected: isSelected))

                Text(filter.label)
                    .font(.system(size: Theme.metaSize, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 1)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.field)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter by \(filter.label)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func iconColor(for filter: SmartFilter, isSelected: Bool) -> Color {
        if filter == .pinned {
            return Theme.bookmark
        }
        return isSelected ? Theme.accent : .secondary
    }
}
