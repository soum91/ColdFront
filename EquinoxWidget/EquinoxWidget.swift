import SwiftUI
import WidgetKit
import AppIntents

@main struct EquinoxWidgets: WidgetBundle {
    var body: some Widget {
        EquinoxRoomWidget()
        EquinoxTemperatureWidget()
        if #available(iOS 18.0, *) { EquinoxPowerControl(); EquinoxActionControl() }
    }
}
struct ACEntry: TimelineEntry {
    var date: Date
    var state: ACWidgetState?
    static func make(_ id: String?) -> ACEntry {
        let list = ACWidgetState.load()
        let state = id == nil ? list.first : (list.first { $0.id == id } ?? (list.count == 1 ? list.first : nil))
        return .init(date: .now, state: state)
    }
}
struct ACProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ACEntry { .make(nil) }
    func snapshot(for configuration: ACWidgetConfig, in context: Context) async -> ACEntry { .make(configuration.device?.id) }
    func timeline(for configuration: ACWidgetConfig, in context: Context) async -> Timeline<ACEntry> {
        Timeline(entries: [.make(configuration.device?.id)], policy: .after(.now.addingTimeInterval(900)))
    }
}
struct EquinoxRoomWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "EquinoxRoom", intent: ACWidgetConfig.self, provider: ACProvider()) { ACWidgetView(entry: $0).containerBackground(for: .widget) { Color.clear } }
            .configurationDisplayName("Room & AC").description("Room and target temperature, AC power and mode.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
// A dedicated, read-only 1-slot Lock Screen temperature widget.
// The existing Room & AC circle remains an interactive power switch.
// The single-slot temperature display has no required configuration.
// Use the same static timeline approach as the working DewPoint temperature widget;
// this also gives an unconfigured widget a real rendered view.
struct ACStaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> ACEntry { .make(nil) }
    func getSnapshot(in context: Context, completion: @escaping (ACEntry) -> Void) {
        completion(.make(nil))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ACEntry>) -> Void) {
        completion(Timeline(entries: [.make(nil)], policy: .after(.now.addingTimeInterval(900))))
    }
}

struct EquinoxTemperatureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EquinoxTemperatureStatic", provider: ACStaticProvider()) { entry in
            EquinoxTemperatureView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Room temperature")
        .description("Latest room temperature from Equinox. Opens without choosing an AC.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct EquinoxTemperatureView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ACEntry

    var body: some View {
        let room = entry.state?.room.map {
            String(format: "%.1f%@", $0, entry.state?.unit ?? "°C")
        } ?? "--"

        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 14, weight: .medium))
                        Text(room)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "thermometer.medium")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.state?.name ?? "Room")
                            .font(.caption2)
                            .lineLimit(1)
                        Text(room)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
    }
}

struct ACWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ACEntry
    var body: some View {
        if let s = entry.state {
            let room = s.room.map { String(format: "%.1f%@", $0, s.unit) } ?? "--"
            if family == .accessoryInline {
                Text("\(s.name) \(room) → \(s.target.map(String.init) ?? "--")° · \(s.on ? s.mode : "Off")")
            } else if family == .accessoryCircular {
                Button(intent: ACToggleIntent(s.id)) { ZStack { AccessoryWidgetBackground(); VStack(spacing: 1) {
                    Image(systemName: s.on ? "snowflake" : "power"); Text(room).font(.caption.bold()).minimumScaleFactor(0.5)
                } } }.buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(s.name).font(.caption.bold()).lineLimit(1); Spacer(); Button(intent: ACToggleIntent(s.id)) { Image(systemName: "power") }.buttonStyle(.plain) }
                    Text("\(room) → \(s.target.map(String.init) ?? "--")°").font(.headline).minimumScaleFactor(0.6)
                    Text(s.on ? s.mode : "Off").font(.caption)
                    Text("Updated \(s.updatedAt, style: .relative) ago").font(.caption2).foregroundStyle(.secondary)
                    if family == .systemSmall || family == .systemMedium {
                        HStack {
                            Button(intent: ACActionIntent(s.id, .cooler)) { Label("Cooler", systemImage: "minus") }
                            Button(intent: ACActionIntent(s.id, .warmer)) { Label("Warmer", systemImage: "plus") }
                        }.labelStyle(.iconOnly).buttonStyle(.bordered)
                    }
                }
            }
        } else if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "thermometer.medium")
                    Text("--").font(.caption.bold())
                }
            }
        } else if family == .accessoryInline {
            Label("AC --", systemImage: "thermometer.medium")
        } else {
            Label("Open Equinox to load your AC", systemImage: "thermometer.medium")
                .font(.caption)
        }
    }
}
@available(iOS 18.0, *) struct ACControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: ACControlConfig) -> ACEntry { .make(configuration.device?.id) }
    func currentValue(configuration: ACControlConfig) async throws -> ACEntry { .make(configuration.device?.id) }
}
@available(iOS 18.0, *) struct EquinoxPowerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.soum91.coldfront.power", provider: ACControlProvider()) { entry in
            ControlWidgetToggle(entry.state?.name ?? "AC", isOn: entry.state?.on ?? false, action: ACPowerIntent(entry.state?.id ?? "")) {
                Label($0 ? "On" : "Off", systemImage: "snowflake")
            }
        }.displayName("AC power").description("Switch your selected AC on or off.")
    }
}
@available(iOS 18.0, *) struct EquinoxActionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.soum91.coldfront.action", intent: ACControlConfig.self) { configuration in
            ControlWidgetButton(action: ACActionIntent(configuration.device?.id ?? "", configuration.action)) {
                Label(configuration.action.rawValue.capitalized, systemImage: configuration.action.symbol)
            }
        }.displayName("AC action").description("Add separate temperature, mode, Sleep or Eco buttons.")
    }
}
