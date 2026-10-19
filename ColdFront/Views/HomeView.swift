import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background(Color(red: 0.3, green: 0.7, blue: 1))
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        if let e = store.error {
                            Label(e, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .card()
                        }
                        if store.appliances.isEmpty {
                            empty
                        }
                        ForEach(store.appliances) { a in
                            NavigationLink(value: a.id) {
                                DeviceCard(appliance: a)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
                .refreshable { await store.refresh() }
            }
            .navigationDestination(for: String.self) { id in
                ControlView(id: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting).font(.system(size: 30, weight: .bold, design: .rounded))
            if let t = store.lastUpdated {
                Text("Updated \(t.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 6)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            if store.lastUpdated == nil {
                ProgressView()
            } else {
                Image(systemName: "air.conditioner.horizontal").font(.largeTitle).foregroundStyle(.secondary)
                Text("No devices on this account").font(.headline)
                Text("Add the AC in the official app first. It shows up here once it's bound to your account.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}

struct DeviceCard: View {
    @EnvironmentObject var store: Store
    let appliance: Appliance

    var body: some View {
        let a = appliance
        let accent = Theme.accent(a)
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(accent.opacity(0.18)).frame(width: 52, height: 52)
                Image(systemName: a.isAirConditioner ? "air.conditioner.vertical" : "questionmark.square.dashed")
                    .font(.title2).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(a.name).font(.headline)
                Text(subtitle(a)).font(.subheadline).foregroundStyle(.secondary)
                if let alert = a.alerts.first {
                    Text(alert).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if a.isAirConditioner && a.online {
                Button {
                    store.setPower(a, !a.isOn)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 46, height: 46)
                        .background(a.isOn ? accent : Color.white.opacity(0.08), in: Circle())
                        .foregroundStyle(a.isOn ? .black : .white)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact, trigger: a.isOn)
            }
        }
        .card()
    }

    private func subtitle(_ a: Appliance) -> String {
        if !a.online { return "Offline" }
        guard a.isAirConditioner else { return a.typeName }
        var parts: [String] = []
        if a.isOn, let smart = store.smartAuto(a) {
            let phase = a.mode == .cool ? "cooling" : (a.mode == .heat ? "heating" : "idle")
            parts.append("Auto, \(phase)")
            parts.append("Set \(smart.target(for: a))\(a.unitSymbol)")
        } else if a.isOn {
            parts.append(a.mode.label)
            if a.mode.allowsTemperature, let t = a.targetTemp { parts.append("Set \(t)\(a.unitSymbol)") }
        } else {
            parts.append("Off")
        }
        if let i = a.indoorTemp { parts.append("Room \(i)\(a.unitSymbol)") }
        return parts.joined(separator: " · ")
    }
}
