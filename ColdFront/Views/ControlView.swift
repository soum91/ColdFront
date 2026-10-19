import SwiftUI
import UIKit

struct ControlView: View {
    @EnvironmentObject var store: Store
    let id: String
    @State private var showEnergy = false
    @State private var showRaw = false

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
                    section("Functions") { functions(a, accent) }
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
        .navigationTitle(a.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    // MARK: Pieces

    private func roomStats(_ a: Appliance) -> some View {
        HStack(spacing: 12) {
            stat("Indoor", a.indoorTemp.map { "\($0)\(a.unitSymbol)" } ?? "--", "thermometer.medium")
            if let h = a.humidity {
                stat("Humidity", "\(h)%", "humidity")
            }
            if let w = a.int(P.watts) {
                stat("Power", "\(w) W", "bolt")
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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
