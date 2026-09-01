import SwiftUI

/// The search field along the top of the board.
///
/// A real `TextField` rather than characters accumulated from the key monitor.
/// Hand-rolling the field would be simpler and would lose input methods
/// entirely — no Japanese, no Chinese, no dead keys — which for an app whose
/// whole point is finding text you have already handled would be a strange thing
/// to give up. It also gets paste, selection and a caret for nothing.
struct SearchBar: View {

    @Bindable var model: BoardModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(model.isSearching ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))

            TextField("Search — try app:xcode, type:image, has:text", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: Theme.titleSize))
                .focused($isFocused)
                // Return, arrows and Escape are the board's, and the key monitor
                // takes them before they reach here. This is only ever text.
                .onSubmit { model.paste() }

            if model.isSearching {
                Text(resultSummary)
                    .font(.system(size: Theme.metaSize))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())

                Button {
                    model.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .padding(.horizontal, Theme.gutter)
        .frame(height: Theme.searchBarHeight)
        .animation(Theme.Motion.contentIn, value: model.isSearching)
        .animation(Theme.Motion.contentIn, value: model.resultCount)
        // The board is summoned to find something, so the caret starts here and
        // typing works without aiming at anything first.
        .onAppear { isFocused = true }
        .onChange(of: model.isVisibleGeneration) { isFocused = true }
    }

    private var resultSummary: String {
        model.resultCount == 1 ? "1 result" : "\(model.resultCount) results"
    }
}
