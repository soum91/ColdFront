import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var lastPublished: Date?

    private var widgetSnapshots: [ACWidgetState] { ACWidgetState.load() }

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
                Section("Lock Screen widget diagnostics") {
                    LabeledContent("Shared container", value: AppGroup.isShared ? "Connected" : "Unavailable")
                    LabeledContent("Group", value: AppGroup.activeGroup ?? "No shared group")
                        .font(.caption)
                    LabeledContent("ACs in app", value: "\(store.appliances.filter(\.isAirConditioner).count)")
                    LabeledContent("Shared AC snapshots", value: "\(widgetSnapshots.count)")
                    if let ac = store.appliances.first(where: \.isAirConditioner) {
                        LabeledContent("App room temperature",
                                       value: store.roomTemp(ac).value.map { String(format: "%.1f%@", $0, ac.unitSymbol) } ?? "--")
                    }
                    if let snap = widgetSnapshots.first {
                        LabeledContent("Widget temperature",
                                       value: snap.room.map { String(format: "%.1f%@", $0, snap.unit) } ?? "--")
                        LabeledContent("Saved at", value: snap.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button("Refresh AC and widget now") {
                        Task {
                            await store.refresh()
                            store.publishWidgetState()
                            lastPublished = .now
                        }
                    }
                    if let lastPublished {
                        Text("Last publish: \(lastPublished, style: .time)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("If the app has a room temperature but the widget snapshot is empty, send a screenshot of this section.")
                        .font(.caption).foregroundStyle(.secondary)
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
