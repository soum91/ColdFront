import SwiftUI
import WidgetKit
import AppIntents

@main struct EquinoxWidgets: WidgetBundle {
    var body: some Widget {
        EquinoxHomeWidget()
        EquinoxTemperatureWidget()
        EquinoxGoveeWidget()
        if #available(iOS 18.0, *) { EquinoxPowerControl(); EquinoxActionControl() }
    }
}
struct ACEntry: TimelineEntry {
    var date: Date
    var state: ACWidgetState?
    var room: [TempPoint] = []
    var set: [TempPoint] = []
    var start: Date = .now.addingTimeInterval(-12 * 3600)
    var end: Date = .now

    static func make(_ id: String?) -> ACEntry {
        let list = ACWidgetState.load()
        let state = id.flatMap { chosen in list.first { $0.id == chosen } } ?? list.first
        let end = Date(), start = end.addingTimeInterval(-12 * 3600)
        let wire = state.flatMap { ACHistoryWire.load()[$0.id] }
        return .init(date: end, state: state,
                     room: (wire?.room ?? []).filter { $0.t >= start },
                     set: (wire?.set ?? []).filter { $0.t >= start },
                     start: start, end: end)
    }

    static var preview: ACEntry {
        let end = Date(), start = end.addingTimeInterval(-12 * 3600)
        let vals: [Double] = [23.4, 23.1, 22.6, 22.0, 21.6, 21.3, 21.2, 21.4, 21.1, 20.9, 21.0, 21.2, 21.1, 20.9, 21.0]
        let pts = vals.enumerated().map { i, v in
            TempPoint(t: start.addingTimeInterval(Double(i) / Double(vals.count - 1) * 12 * 3600), v: v)
        }
        let st = ACWidgetState(id: "preview", name: "Portable AC", on: true, room: 21.0, target: 21, unit: "°C",
                               mode: "Smart Auto", updatedAt: end, phase: "cool", online: true)
        return .init(date: end, state: st, room: pts, set: [TempPoint(t: start, v: 21)], start: start, end: end)
    }

    var color: Color { EquinoxColor.of(state?.phase) }
}

// Static configuration + cached data only: the configurable (AppIntentConfiguration) kind never
// gets a timeline on these sideloaded builds and sits on its grey placeholder (same as FindMyBLE).
struct ACHomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ACEntry { .preview }
    func getSnapshot(in context: Context, completion: @escaping (ACEntry) -> Void) {
        let e = ACEntry.make(nil)
        completion(context.isPreview && e.state == nil ? .preview : e)
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ACEntry>) -> Void) {
        completion(Timeline(entries: [.make(nil)], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct EquinoxHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EquinoxAC.v2", provider: ACHomeProvider()) { entry in
            ACHomeView(entry: entry)
        }
        .configurationDisplayName("Equinox")
        .description("Room temperature, what the AC is doing and the last 12 hours.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: Home screen views (Exhale style)

struct ACPowerButton: View {
    let s: ACWidgetState
    let color: Color
    var body: some View {
        Button(intent: ACToggleIntent(s.id)) {
            Image(systemName: "power")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(s.on ? Color.black : Color.white.opacity(0.75))
                .frame(width: 30, height: 30)
                .background(Circle().fill(s.on ? color : Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}

struct ACTempBlock: View {
    let entry: ACEntry
    var big: CGFloat = 44
    var body: some View {
        let s = entry.state
        VStack(alignment: .leading, spacing: 2) {
            Text("ROOM")
                .font(.system(size: 10, weight: .semibold)).tracking(1)
                .foregroundStyle(.white.opacity(0.55))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(s?.room.map { String(format: "%.1f", $0) } ?? "--")
                    .font(.system(size: big, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(s?.unit ?? "°C")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            HStack(spacing: 5) {
                Circle().fill(entry.color).frame(width: 7, height: 7)
                Text(ACHomeView.status(s))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(entry.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

struct ACWidgetBackground: View {
    let color: Color
    let on: Bool
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.08, blue: 0.12), Color(red: 0.02, green: 0.03, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [color.opacity(on ? 0.35 : 0.12), .clear],
                           center: .topLeading, startRadius: 5, endRadius: 220)
        }
    }
}

struct ACGraph: View {
    let entry: ACEntry
    var lineWidth: CGFloat = 2
    var body: some View {
        let b = TempSeries.bounds(entry.room.map(\.v) + entry.set.map(\.v))
        ZStack {
            if entry.room.count < 2 {
                Text("Graph fills in as readings come in")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            } else {
                if !entry.set.isEmpty {
                    StepShape(points: entry.set, start: entry.start, end: entry.end, lo: b.lo, hi: b.hi)
                        .stroke(Color.yellow.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                TempCurve(points: entry.room, start: entry.start, end: entry.end, lo: b.lo, hi: b.hi,
                          color: entry.color == EquinoxColor.off ? EquinoxColor.cool : entry.color, lineWidth: lineWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ACEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "air.conditioner.vertical").font(.title2).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(AppGroup.isShared ? "Open Equinox to load your AC." : "Widget can't open the shared folder (v\(AppGroup.version)). Remove this widget and add it again.")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct ACHomeView: View {
    @Environment(\.widgetFamily) var family
    let entry: ACEntry

    static func status(_ s: ACWidgetState?) -> String {
        guard let s else { return "No data" }
        if s.online == false { return "Offline" }
        guard s.on else { return "Off" }
        let to = s.target.map { " to \($0)\(s.unit)" } ?? ""
        if s.mode == "Smart Auto" {
            let p = s.phase == "cool" ? "cooling" : s.phase == "heat" ? "heating" : "idle"
            return "Auto, \(p)\(to)"
        }
        return s.phase == "cool" || s.phase == "heat" ? "\(s.mode)\(to)" : s.mode
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            case .systemLarge: large
            case .accessoryRectangular: rectangular
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: small
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall || family == .systemMedium || family == .systemLarge {
                ACWidgetBackground(color: entry.color, on: entry.state?.on ?? false)
            } else {
                Color.clear
            }
        }
        .widgetURL(URL(string: "equinox://open"))
    }

    @ViewBuilder private var small: some View {
        if let s = entry.state {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(s.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                    Spacer(minLength: 4)
                    ACPowerButton(s: s, color: entry.color)
                }
                Spacer(minLength: 0)
                ACTempBlock(entry: entry, big: 40)
            }
        } else { ACEmptyState() }
    }

    @ViewBuilder private var medium: some View {
        if let s = entry.state {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Text(s.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                        Spacer(minLength: 4)
                        ACPowerButton(s: s, color: entry.color)
                    }
                    Spacer(minLength: 0)
                    ACTempBlock(entry: entry, big: 38)
                }
                .frame(width: 132)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Last 12 h").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Text(s.updatedAt, style: .time).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    }
                    ACGraph(entry: entry)
                    HStack {
                        Text(entry.start, format: .dateTime.hour())
                        Spacer()
                        Text("Now")
                    }
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                }
            }
        } else { ACEmptyState() }
    }

    @ViewBuilder private var large: some View {
        if let s = entry.state {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(s.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    ACPowerButton(s: s, color: entry.color)
                }
                ACTempBlock(entry: entry, big: 52)
                Text("Last 12 hours").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                ACGraph(entry: entry, lineWidth: 2.5)
                HStack {
                    Text(entry.start, format: .dateTime.hour())
                    Spacer()
                    Text(entry.start.addingTimeInterval(6 * 3600), format: .dateTime.hour())
                    Spacer()
                    Text("Now")
                }
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                if s.on {
                    HStack(spacing: 10) {
                        Button(intent: ACActionIntent(s.id, .cooler)) { Label("Cooler", systemImage: "minus") }
                        Button(intent: ACActionIntent(s.id, .warmer)) { Label("Warmer", systemImage: "plus") }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
        } else { ACEmptyState() }
    }

    private var rectangular: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text("ROOM").font(.system(size: 10, weight: .semibold)).opacity(0.7)
                Text(entry.state?.room.map { String(format: "%.1f°", $0) } ?? "--")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(ACHomeView.status(entry.state)).font(.system(size: 10)).lineLimit(1)
            }
            if entry.room.count >= 2 {
                let b = TempSeries.bounds(entry.room.map(\.v))
                TempCurveShape(points: entry.room, start: entry.start, end: entry.end, lo: b.lo, hi: b.hi)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .widgetAccentable()
            }
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: entry.state?.on == true ? (entry.state?.phase == "heat" ? "sun.max.fill" : "snowflake") : "power")
                    .font(.system(size: 12, weight: .semibold))
                Text(entry.state?.room.map { String(format: "%.0f°", $0) } ?? "--")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
        }
    }

    private var inline: some View {
        Text("\(entry.state?.room.map { String(format: "%.1f°", $0) } ?? "--") · \(ACHomeView.status(entry.state))")
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
                VStack(spacing: 1) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 16, weight: .semibold))
                    Text(room)
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

@available(iOS 18.0, *) struct ACControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: ACControlConfig) -> ACEntry { .make(configuration.device?.id) }
    func currentValue(configuration: ACControlConfig) async throws -> ACEntry { .make(configuration.device?.id) }
}
@available(iOS 18.0, *) struct EquinoxPowerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.soum91.coldfront.power", provider: ACControlProvider()) { entry in
            ControlWidgetToggle(entry.state?.name ?? "AC", isOn: entry.state?.on ?? false, action: ACPowerIntent(entry.state?.id ?? "")) {
                Image(systemName: $0 ? "power.circle.fill" : "power")
                    .controlWidgetActionHint($0 ? "Turn off AC" : "Turn on AC")
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

// MARK: - Govee sensor widget

struct GoveeEntry: TimelineEntry {
    var date: Date
    var state: GoveeWidgetState?
    var temp: String {
        guard let s = state else { return "--" }
        return String(format: "%.1f%@", s.fahrenheit ? s.tempC * 9 / 5 + 32 : s.tempC, s.fahrenheit ? "°F" : "°C")
    }
    /// The bridge's reading when it is newer than the one the app saved (the app can't listen in the background).
    static func fresh() async -> GoveeEntry {
        var st = GoveeWidgetState.load()
        if let b = await GoveeFeed.fetchBridge(), b.at > (st?.at ?? .distantPast) { st = b }
        return .init(date: .now, state: st)
    }
}

struct GoveeProvider: TimelineProvider {
    func placeholder(in context: Context) -> GoveeEntry {
        .init(date: .now, state: GoveeWidgetState(name: "Govee", tempC: 21.5, humidity: 45, battery: 90, at: .now, fahrenheit: false))
    }
    func getSnapshot(in context: Context, completion: @escaping (GoveeEntry) -> Void) {
        let s = GoveeWidgetState.load()
        completion(s == nil ? placeholder(in: context) : .init(date: .now, state: s))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<GoveeEntry>) -> Void) {
        Task { completion(Timeline(entries: [await GoveeEntry.fresh()], policy: .after(.now.addingTimeInterval(600)))) }
    }
}

struct EquinoxGoveeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EquinoxGovee", provider: GoveeProvider()) { entry in
            GoveeWidgetView(entry: entry).containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Govee room sensor")
        .description("Room temperature and humidity from your Govee, read from the Keystone Bridge so it stays current.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct GoveeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GoveeEntry

    var body: some View {
        let s = entry.state
        let hum = s.map { String(format: "%.0f%%", $0.humidity) } ?? "--"
        switch family {
        case .accessoryInline:
            Text("\(entry.temp) · \(hum)")
        case .accessoryCircular:
            VStack(spacing: 1) {
                Image(systemName: "thermometer.medium").font(.system(size: 16, weight: .semibold))
                Text(entry.temp).font(.system(size: 11, weight: .bold)).lineLimit(1).minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "thermometer.medium")
                VStack(alignment: .leading, spacing: 1) {
                    Text(s?.name.replacingOccurrences(of: " (bridge)", with: "") ?? "Govee").font(.caption2).lineLimit(1)
                    Text("\(entry.temp) · \(hum)").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 3) {
                Label(s?.name.replacingOccurrences(of: " (bridge)", with: "") ?? "Govee", systemImage: "thermometer.medium")
                    .font(.caption.bold()).lineLimit(1)
                Text(entry.temp).font(.title.bold()).minimumScaleFactor(0.6)
                Text("\(hum) humidity").font(.caption)
                if let s {
                    Text("Updated \(s.at, style: .relative) ago").font(.caption2).foregroundStyle(.secondary)
                    if s.usedByAuto { Text("Used by Smart").font(.caption2).foregroundStyle(.secondary) }
                } else {
                    Text("Open Equinox once").font(.caption2)
                }
            }
        }
    }
}
