import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Signed in as", value: store.savedUsername)
                    Button("Sign out", role: .destructive) {
                        store.logout()
                        dismiss()
                    }
                }
                Section("Devices") {
                    ForEach(store.appliances) { a in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name)
                            Text("\(a.typeName) · \(a.typeCode)-\(a.featureCode)\(a.room.isEmpty ? "" : " · \(a.room)")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Automations") {
                    Text("Scenes show up as actions in the Shortcuts app (Run Scene, Turn On/Off AC, Set AC Temperature, Get Room Temperature). For schedules, open Shortcuts → Automation → New, pick Time of Day (or Arrive, Leave, Alarm, Focus), choose Run Immediately, and add an Equinox action. These run on time even when Equinox is closed. For conditions, use Get Room Temperature inside an If block.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text("Equinox talks to the same cloud service as the official ConnectLife app. Devices are added and Wi-Fi provisioned in the official app; this app handles day-to-day control. Status refreshes every 20 seconds while the app is open.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Protocol research credit: oyvindwe/connectlife and bilan/connectlife-api-connector. Not affiliated with Hisense or ConnectLife.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
