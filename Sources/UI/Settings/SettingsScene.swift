import SwiftUI

/// What the Settings window can ask the rest of the app to do.
///
/// Closures rather than a reference to the coordinator: it keeps the settings
/// views from reaching into anything they were not handed, and it is what lets
/// them be looked at without an app around them.
@MainActor
struct SettingsActions {
    var reregisterHotkeys: () -> Void = {}
    var applyExclusions: () -> Void = {}
    var applyRetention: () -> Void = {}
    var clipCount: () -> Int = { 0 }
    var clearHistory: () -> Void = {}
}

struct SettingsScene: View {

    @Bindable var preferences: Preferences
    var actions = SettingsActions()

    var body: some View {
        TabView {
            GeneralSettings(preferences: preferences, actions: actions)
                .tabItem { Label("General", systemImage: "gearshape") }

            HistorySettings(preferences: preferences, actions: actions)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            RecognitionSettings(preferences: preferences)
                .tabItem { Label("Text", systemImage: "text.viewfinder") }

            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        // Sized to the tallest tab rather than left to shrink-wrap the one that
        // happens to be showing: a Settings window that resizes as you move
        // between tabs is disorienting, and one sized to the shortest tab quietly
        // hides the bottom of the others.
        .frame(width: 480, height: 440)
    }
}

// MARK: - General

private struct GeneralSettings: View {

    @Bindable var preferences: Preferences
    let actions: SettingsActions

    var body: some View {
        Form {
            Section {
                LabeledContent("Show clipboard") {
                    HotkeyRecorder(combination: $preferences.showBoardHotkey)
                }
                LabeledContent("Capture to text") {
                    HotkeyRecorder(
                        combination: $preferences.captureToTextHotkey,
                        isEnabled: preferences.isCaptureToTextEnabled
                    )
                }
                Toggle("Enable capture to text", isOn: $preferences.isCaptureToTextEnabled)
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("A shortcut another app already uses will not fire.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .onChange(of: preferences.showBoardHotkey) { actions.reregisterHotkeys() }
            .onChange(of: preferences.captureToTextHotkey) { actions.reregisterHotkeys() }
            .onChange(of: preferences.isCaptureToTextEnabled) { actions.reregisterHotkeys() }

            Section("Appearance") {
                Picker("Board position", selection: $preferences.boardEdge) {
                    Text("Top of the screen").tag(BoardEdge.top)
                    Text("Bottom of the screen").tag(BoardEdge.bottom)
                }
                .pickerStyle(.radioGroup)
            }

            Section("Startup") {
                Toggle("Open Copas at login", isOn: Binding(
                    get: { preferences.launchesAtLogin },
                    set: { preferences.launchesAtLogin = $0 }
                ))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - History

private struct HistorySettings: View {

    @Bindable var preferences: Preferences
    let actions: SettingsActions

    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Keep at most") {
                    HStack(spacing: 6) {
                        TextField(
                            "",
                            value: $preferences.maximumClipCount,
                            format: .number
                        )
                        .labelsHidden()
                        .frame(width: 70)
                        Text(preferences.maximumClipCount > 0 ? "clips" : "clips (no limit)")
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Delete after") {
                    HStack(spacing: 6) {
                        TextField(
                            "",
                            value: $preferences.maximumClipAgeInDays,
                            format: .number
                        )
                        .labelsHidden()
                        .frame(width: 70)
                        Text(preferences.maximumClipAgeInDays > 0 ? "days" : "days (never)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Retention")
            } footer: {
                Text("Zero means no limit. Trimming runs at launch.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .onChange(of: preferences.maximumClipCount) { actions.applyRetention() }
            .onChange(of: preferences.maximumClipAgeInDays) { actions.applyRetention() }

            Section {
                ExcludedAppList(preferences: preferences, actions: actions)
            } header: {
                Text("Never record")
            } footer: {
                Text("""
                    Password managers are skipped automatically when they mark \
                    what they copy. This is for apps that do not.
                    """)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Section("Everything") {
                LabeledContent("\(actions.clipCount()) clips stored") {
                    Button("Delete All…", role: .destructive) { isConfirmingClear = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Delete every clip?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { actions.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

private struct ExcludedAppList: View {

    @Bindable var preferences: Preferences
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if preferences.excludedBundleIDs.isEmpty {
                Text("No apps excluded.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(preferences.excludedBundleIDs, id: \.self) { bundleID in
                    HStack(spacing: 8) {
                        if let icon = AppIconCache.shared.icon(for: bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "app.dashed").foregroundStyle(.tertiary)
                        }
                        Text(InstalledApps.displayName(for: bundleID))
                        Spacer(minLength: 8)
                        Button {
                            preferences.include(bundleID)
                            actions.applyExclusions()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Record copies from this app again")
                    }
                }
            }

            Button("Add App…") {
                guard let bundleID = InstalledApps.chooseApplication() else { return }
                preferences.exclude(bundleID)
                AppIconCache.shared.prewarm([bundleID])
                actions.applyExclusions()
            }
        }
        .onAppear { AppIconCache.shared.prewarm(preferences.excludedBundleIDs) }
    }
}

// MARK: - Recognition

private struct RecognitionSettings: View {

    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Read text in copied images", isOn: $preferences.recognizesTextInImages)
                Toggle("Copy the image when a capture has no text",
                       isOn: $preferences.copiesImageWhenNoTextFound)
            } header: {
                Text("Recognition")
            } footer: {
                Text("""
                    Recognition runs on this Mac. No image and no recognised text \
                    leaves the machine.
                    """)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Section("Permission") {
                LabeledContent("Screen Recording") {
                    if RegionCapture.isPermitted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings…") {
                            RegionCapture.requestPermission()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutSettings: View {

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.accent)

            VStack(spacing: 3) {
                Text("Copas").font(.system(size: 16, weight: .semibold))
                Text(version).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Text("A clipboard manager for macOS.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Link("github.com/sigitkusuma/copas",
                 destination: URL(string: "https://github.com/sigitkusuma/copas")!)
                .font(.system(size: 11))

            Divider().padding(.horizontal, 40)

            VStack(spacing: 4) {
                Text("Copas is free software under the MIT licence.")
                Text("It uses Sparkle and GRDB, both MIT licensed.")
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
