import SwiftUI
import UIKit

struct ControlView: View {
    @EnvironmentObject var store: Store
    let id: String
    var onSettings: (() -> Void)? = nil
    @AppStorage("selectedDevice") private var selectedID = ""
    @State private var showEnergy = false
    @State private var showRaw = false
    @State private var showGovee = false
    @ObservedObject private var govee = Govee.shared

    var body: some View {
        if let a = store.appliance(id) {
            content(a)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func content(_ a: Appliance) -> some View {
        let accent = Theme.accent(a)
        ZStack {
            Theme.background(accent).animation(.easeInOut(duration: 0.4), value: accent)
            ScrollView {
                VStack(spacing: 18) {
                    header(a)
                    roomStats(a)

                    ForEach(a.alerts, id: \.self) { alert in
                        Label(alert, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    }

                    if !a.online {
                        Label("Device is offline. Check that it's plugged in and on Wi-Fi.", systemImage: "wifi.slash")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    }

                    TemperatureDial(appliance: a, accent: accent)
                        .padding(.vertical, 8)
                        .disabled(!a.online)

                    powerButton(a, accent)

                    section("Mode") {
                        modeRow(a, accent)
                        if let sa = store.smartAuto(a) {
                            let band = sa.band(for: a)
                            Stepper(value: Binding(get: { band }, set: { store.setBand(a, $0) }),
                                    in: (a.fahrenheit ? 2 : 1)...(a.fahrenheit ? 10 : 6)) {
                                Text("Switch at ±\(band)\(a.unitSymbol)").font(.subheadline)
                            }
                            Text(a.heatSupported
                                 ? "Cools once the room is \(band)° above your set temp, heats once it's \(band)° below. The unit's own thermostat handles everything in between. Mode changes need the reading to hold 5 min and stay at least 30 min apart."
                                 : "Cools once the room is \(band)° above your set temp, drops to fan once it's \(band)° below (no heat on this unit). Mode changes need the reading to hold 5 min and stay at least 30 min apart.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    section("Fan speed") { fanRow(a, accent) }
                    ScenesRow()
                    section("Functions") { functions(a, accent) }
                    section("Temperature history") { HistoryChart(appliance: a) }
                    section("Energy") { energy(a, accent) }

                    if let e = store.error {
                        Text(e).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding(20)
                .disabled(!a.online)
                .opacity(a.online ? 1 : 0.6)
            }
            .refreshable { await store.refresh() }
        }
        .sheet(isPresented: $showRaw) { RawStatusView(appliance: a) }
        .sheet(isPresented: $showGovee) { GoveePickerView(appliance: a) }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Header (Subwave-style: big name, live status, round buttons)

    private func statusText(_ a: Appliance) -> (String, Color) {
        if !a.online { return ("Offline", .red) }
        if !a.isOn { return ("Off", Color(white: 0.55)) }
        if let s = store.smartAuto(a) {
            let phase = a.mode == .cool ? "cooling" : a.mode == .heat ? "heating" : "idle"
            return ("Auto, \(phase) to \(s.target(for: a))\(a.unitSymbol)", Theme.accent(a))
        }
        var t = a.mode.label
        if a.mode.allowsTemperature, let v = a.targetTemp { t += " to \(v)\(a.unitSymbol)" }
        return (t, Theme.accent(a))
    }

    private func header(_ a: Appliance) -> some View {
        let (status, color) = statusText(a)
        let acs = store.appliances.filter(\.isAirConditioner)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                if acs.count > 1 {
                    Menu {
                        ForEach(acs) { d in Button(d.name) { selectedID = d.id } }
                    } label: {
                        HStack(spacing: 6) {
                            Text(a.name).font(.system(size: 30, weight: .bold, design: .rounded))
                            Image(systemName: "chevron.down").font(.headline)
                        }
                        .foregroundStyle(.primary)
                    }
                } else {
                    Text(a.name).font(.system(size: 30, weight: .bold, design: .rounded))
                        .lineLimit(2).minimumScaleFactor(0.7)
                }
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(status).foregroundStyle(.secondary)
                }
                .font(.subheadline)
                if let room = a.room.isEmpty ? nil : a.room {
                    Text(room).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            HStack(spacing: 10) {
                moreMenu(a)
                if let onSettings {
                    Button(action: onSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 46, height: 46)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }

    private func moreMenu(_ a: Appliance) -> some View {
                Menu {
                    Picker("Units", selection: Binding(
                        get: { a.fahrenheit },
                        set: { store.setUnit(a, fahrenheit: $0) })) {
                        Text("Celsius").tag(false)
                        Text("Fahrenheit").tag(true)
                    }
                    if a.has(P.beep) {
                        Button(a.flag(P.beep) ? "Turn beep off" : "Turn beep on") { store.toggle(a, P.beep) }
                    }
                    Button("Raw device data") { showRaw = true }
                    Text("Model \(a.typeCode)-\(a.featureCode)")
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 46, height: 46)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .foregroundStyle(.primary)
                }
    }

    // MARK: Pieces

    private func roomStats(_ a: Appliance) -> some View {
        let src = store.roomTemp(a).source
        let autoOn = store.smartAuto(a) != nil
        return HStack(spacing: 12) {
            stat("AC sensor", a.indoorTemp.map { "\($0)\(a.unitSymbol)" } ?? "--", "air.conditioner.vertical",
                 active: autoOn && src == .ac)
            Button { showGovee = true } label: {
                if let r = govee.reading(for: a.id) {
                    let t = a.fahrenheit ? r.tempC * 9 / 5 + 32 : r.tempC
                    stat(r.isFresh ? "Govee" : "Govee (stale)",
                         String(format: "%.1f%@", t, a.unitSymbol),
                         "thermometer.medium",
                         sub: String(format: "%.0f%% humidity", r.humidity),
                         active: autoOn && src == .govee)
                } else {
                    stat("Govee", "Add", "plus.circle")
                }
            }
            .buttonStyle(.plain)
            if let w = a.int(P.watts), w > 0 {
                stat("Power", "\(w) W", "bolt")
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ icon: String,
                      sub: String? = nil, active: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold))
            if let sub { Text(sub).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .overlay(alignment: .topTrailing) {
            if active {
                Text("AUTO").font(.system(size: 9, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.white.opacity(0.15), in: Capsule()).padding(8)
            }
        }
    }

    private func powerButton(_ a: Appliance, _ accent: Color) -> some View {
        Button {
            store.setPower(a, !a.isOn)
        } label: {
            Label(a.isOn ? "Turn off" : "Turn on", systemImage: "power")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(a.isOn ? Color.white.opacity(0.08) : accent.opacity(0.9), in: Capsule())
                .foregroundStyle(a.isOn ? .white : .black)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: a.isOn)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            c()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func modeRow(_ a: Appliance, _ accent: Color) -> some View {
        HStack(spacing: 8) {
            ForEach(a.supportedModes) { m in
                let smartOn = store.smartAuto(a) != nil
                let selected = a.isOn && (m == .auto ? smartOn : (!smartOn && a.mode == m))
                Button { store.setMode(a, m) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: m.symbol).font(.title3)
                        Text(m.label).font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(selected ? accent : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(selected ? .black : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.selection, trigger: a.mode)
    }

    private func fanRow(_ a: Appliance, _ accent: Color) -> some View {
        let speeds: [FanSpeed] = [.auto, .quiet, .low, .medium, .high]
        return HStack(spacing: 8) {
            ForEach(speeds) { f in
                let selected = a.fan == f
                Button { store.setFan(a, f) } label: {
                    VStack(spacing: 6) {
                        FanBars(level: f.level, auto: f == .auto, quiet: f == .quiet)
                        Text(f.label).font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(selected ? accent : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(selected ? .black : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.selection, trigger: a.fan)
    }

    private func functions(_ a: Appliance, _ accent: Color) -> some View {
        let items: [(String, String, String)] = [
            (P.eco, "Eco", "leaf"),
            (P.sleep, "Sleep", "moon.zzz"),
            (P.turbo, "Turbo", "hare"),
            (P.mute, "Silent", "speaker.slash"),
            (P.swing, "Swing", "arrow.up.and.down"),
            (P.dimmer, "Dimmer", "lightbulb.min")
        ].filter { a.has($0.0) }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(items, id: \.0) { item in
                let (key, label, icon) = item
                let on = a.flag(key)
                Button { store.toggle(a, key) } label: {
                    VStack(spacing: 8) {
                        Image(systemName: icon).font(.title3)
                        Text(label).font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(on ? accent : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(on ? .black : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func energy(_ a: Appliance, _ accent: Color) -> some View {
        EnergyPanel(appliance: a, accent: accent)
    }
}

// MARK: - Fan bars glyph

struct FanBars: View {
    let level: Int
    let auto: Bool
    let quiet: Bool
    var body: some View {
        if auto {
            Image(systemName: "fan").font(.title3)
        } else if quiet {
            Image(systemName: "wind").font(.title3)
        } else {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(1...3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .frame(width: 5, height: CGFloat(6 + i * 5))
                        .opacity(i <= level ? 1 : 0.25)
                }
            }
            .frame(height: 22)
        }
    }
}

// MARK: - Energy

struct EnergyPanel: View {
    @EnvironmentObject var store: Store
    let appliance: Appliance
    let accent: Color
    @State private var stat = "day"
    @State private var total: Double?
    @State private var curve: [(String, Double)] = []
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $stat) {
                Text("Today").tag("day")
                Text("Week").tag("week")
                Text("Month").tag("month")
            }
            .pickerStyle(.segmented)

            HStack(alignment: .firstTextBaseline) {
                Text(total.map { String(format: "%.2f", $0) } ?? (loading ? "…" : "--"))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("kWh").foregroundStyle(.secondary)
            }

            if !curve.isEmpty {
                let maxV = max(curve.map(\.1).max() ?? 1, 0.001)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(curve, id: \.0) { point in
                        let v = point.1
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accent)
                            .frame(height: max(2, CGFloat(v / maxV) * 70))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 70, alignment: .bottom)
            }
        }
        .task(id: stat) { await load() }
    }

    private func load() async {
        loading = true
        let (t, c) = await store.energy(appliance, stat: stat)
        total = t
        curve = c.sorted { a, b in
            if let x = Int(a.key), let y = Int(b.key) { return x < y }
            return a.key < b.key
        }.map { ($0.key, $0.value) }
        loading = false
    }
}

// MARK: - Raw status (diagnostics)

struct RawStatusView: View {
    let appliance: Appliance
    @Environment(\.dismiss) private var dismiss

    private var dump: String {
        var lines = ["\(appliance.typeCode)-\(appliance.featureCode) \(appliance.featureName)"]
        lines += appliance.status.keys.sorted().map { "\($0) = \(appliance.status[$0]!)" }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            List(appliance.status.keys.sorted(), id: \.self) { k in
                LabeledContent(k, value: appliance.status[k] ?? "")
                    .font(.system(.footnote, design: .monospaced))
            }
            .navigationTitle("Raw device data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Copy all") { UIPasteboard.general.string = dump }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Govee sensor picker

struct GoveePickerView: View {
    let appliance: Appliance
    @ObservedObject private var govee = Govee.shared
    @Environment(\.dismiss) private var dismiss

    private var linked: String? { govee.links[appliance.id] }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if govee.bluetoothOff {
                        Label("Bluetooth is off or not allowed for Equinox.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    let found = govee.readings.values.sorted { $0.rssi > $1.rssi }
                    if found.isEmpty && !govee.bluetoothOff {
                        HStack { ProgressView(); Text("Listening for Govee sensors…").foregroundStyle(.secondary) }
                    }
                    ForEach(found) { r in
                        Button {
                            govee.links[appliance.id] = r.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name)
                                    Text(String(format: "%.1f°C · %.0f%% · battery %d%% · signal %d", r.tempC, r.humidity, r.battery, r.rssi))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if linked == r.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Nearby sensors")
                } footer: {
                    Text("The Govee broadcasts its readings, so no pairing is needed. If it doesn't show up, force-quit the Govee app: while it's connected, the sensor may stop broadcasting. It only updates while Equinox is open; in the background Auto falls back to the AC's own sensor.")
                }

                let unparsed = govee.raw.values.filter { govee.readings[$0.id] == nil }.sorted { $0.rssi > $1.rssi }
                if !unparsed.isEmpty {
                    Section {
                        ForEach(unparsed) { r in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(r.name) · signal \(r.rssi)")
                                Text(r.hex).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    } header: {
                        Text("Seen but not decoded")
                    } footer: {
                        Text("If your sensor shows up here instead of above, screenshot this and send it over.")
                    }
                }

                if linked != nil {
                    Section {
                        Toggle("Auto uses AC sensor only", isOn: Binding(
                            get: { govee.acOnly[appliance.id] == true },
                            set: { govee.acOnly[appliance.id] = $0 }))
                        Button("Unlink sensor", role: .destructive) {
                            govee.links[appliance.id] = nil
                        }
                    } footer: {
                        Text("When on, the Govee is shown for comparison but Auto acts on the AC's reading.")
                    }
                }
            }
            .navigationTitle("Room sensor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { govee.start() }
        }
    }
}
