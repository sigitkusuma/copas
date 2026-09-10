import SwiftUI

/// The Statistics tab in the Settings window.
///
/// Displays aggregate metrics across the user's clipboard history: total clips,
/// text vs. images ratio, storage footprint, and top source applications.
struct StatsSettings: View {

    let actions: SettingsActions
    @State private var stats = ClipboardStats()
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                metricCards

                topAppsSection
            }
            .padding(18)
        }
        .onAppear { loadStats() }
    }

    private func loadStats() {
        stats = actions.fetchStats()
        isLoading = false
    }

    // MARK: - Metric Cards

    private var metricCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(
                title: "Total History",
                value: "\(stats.totalClips)",
                subtitle: "\(stats.textClips) text · \(stats.imageClips) images",
                icon: "doc.on.clipboard"
            )

            statCard(
                title: "Pinned Snippets",
                value: "\(stats.pinnedClips)",
                subtitle: "Protected from cleanup",
                icon: "pin.fill",
                iconColor: Theme.bookmark
            )

            statCard(
                title: "Recent Activity",
                value: "\(stats.clipsToday) today",
                subtitle: "\(stats.clipsThisWeek) this week",
                icon: "clock.arrow.circlepath"
            )

            statCard(
                title: "Storage Footprint",
                value: stats.formattedStorageSize,
                subtitle: "Indexed SQLite & blobs",
                icon: "internaldrive"
            )
        }
    }

    private func statCard(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        iconColor: Color = Theme.accent
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(iconColor)
            }

            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Top Apps

    private var topAppsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOP SOURCE APPS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            if stats.topApps.isEmpty {
                Text("No clips recorded yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(stats.topApps) { app in
                        appRow(app)
                    }
                }
                .padding(12)
                .background(Theme.field)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func appRow(_ app: AppClipCount) -> some View {
        let maxCount = max(stats.topApps.first?.count ?? 1, 1)
        let ratio = CGFloat(app.count) / CGFloat(maxCount)

        return HStack(spacing: 8) {
            if let icon = AppIconCache.shared.icon(for: app.bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 13))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
            }

            Text(app.name)
                .font(.system(size: 12))
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 6)

                    Capsule()
                        .fill(Theme.accent.opacity(0.7))
                        .frame(width: max(geo.size.width * ratio, 6), height: 6)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 16)

            Text("\(app.count)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}
