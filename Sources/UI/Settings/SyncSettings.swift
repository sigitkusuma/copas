import SwiftUI

struct SyncSettings: View {
    @Bindable var preferences: Preferences
    let actions: SettingsActions

    var body: some View {
        Form {
            Section {
                Toggle("Sync clipboard history via iCloud", isOn: $preferences.isSyncEnabled)
                    .disabled(!CloudKitManager.isEntitled)
                    .onChange(of: preferences.isSyncEnabled) { _, isEnabled in
                        actions.toggleSync(isEnabled)
                    }
            } header: {
                Text("iCloud Sync")
            } footer: {
                if CloudKitManager.isEntitled {
                    Text("Clips are stored in your private iCloud database. Only devices signed into your Apple ID can access them.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("iCloud Sync requires an Apple Developer ID provisioning profile with CloudKit capability enabled for this build.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if preferences.isSyncEnabled && CloudKitManager.isEntitled {
                let status = actions.syncStatus()

                Section("Status") {
                    LabeledContent("iCloud Account") {
                        Text(status?.accountDescription ?? "Checking...")
                            .foregroundStyle((status?.isAccountAvailable ?? false) ? .primary : .secondary)
                    }

                    if let lastSync = status?.lastSyncDate {
                        LabeledContent("Last synced") {
                            Text(lastSync, format: .relative(presentation: .named))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let pendingCount = status?.pendingCount, pendingCount > 0 {
                        LabeledContent("Pending changes") {
                            Text("\(pendingCount) item\(pendingCount == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = status?.errorMessage {
                        LabeledContent("Sync issue") {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                        }
                    }

                    HStack {
                        Spacer()
                        Button {
                            actions.triggerSync()
                        } label: {
                            if status?.isSyncing == true {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Sync Now")
                            }
                        }
                        .disabled(status?.isSyncing == true || !(status?.isAccountAvailable ?? false))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
