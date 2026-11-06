import SwiftUI
import UIKit
import CoreLocation

struct ScenesRow: View {
    @EnvironmentObject var store: Store
    @State private var editing: ACScene?
    @State private var running: String?
    @State private var done: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Scenes").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    let f = store.appliances.first?.fahrenheit ?? false
                    editing = ACScene(name: "", icon: "sparkles", mode: ACMode.auto.rawValue,
                                      temp: f ? 72 : 21, tempFahrenheit: f)
                } label: { Image(systemName: "plus") }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.scenes) { s in
                        Button { run(s) } label: { chip(s) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editing = s }
                                Button("Delete", systemImage: "trash", role: .destructive) { store.deleteScene(s) }
                            }
                    }
                }
            }
            Text("Tap to run, long-press to edit.").font(.caption2).foregroundStyle(.secondary)
        }
        .card()
        .sheet(item: $editing) { s in SceneEditor(scene: s) }
        .sensoryFeedback(.success, trigger: done)
    }

    private func chip(_ s: ACScene) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if running == s.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: done == s.id ? "checkmark" : s.icon)
                }
                Text(s.name).fontWeight(.semibold)
                if s.onArrive == true || s.onLeave == true {
                    Image(systemName: "location.fill").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(s.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minWidth: 110, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private func run(_ s: ACScene) {
        running = s.id
        Task {
            do {
                try await store.runScene(s)
                done = s.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if done == s.id { done = nil } }
            } catch {}
            running = nil
        }
    }
}

struct SceneEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var scene: ACScene
    @ObservedObject private var geo = Geo.shared

    private let icons = ["sparkles", "sofa", "moon.zzz", "bed.double", "sun.max", "snowflake", "flame",
                         "house", "figure.walk", "briefcase", "power", "leaf", "tv", "book"]

    private var heatSupported: Bool { store.appliances.first?.heatSupported ?? true }
    private var range: ClosedRange<Int> { scene.tempFahrenheit ? 61...90 : 16...32 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $scene.name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(icons, id: \.self) { i in
                                Image(systemName: i)
                                    .frame(width: 38, height: 38)
                                    .background(scene.icon == i ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06),
                                                in: RoundedRectangle(cornerRadius: 10))
                                    .onTapGesture { scene.icon = i }
                            }
                        }
                    }
                }

                Section {
                    Toggle("Power on", isOn: $scene.power)
                }

                if scene.power {
                    Section("Mode") {
                        Picker("Mode", selection: $scene.mode) {
                            Text("Don't change").tag(Int?.none)
                            Text("Smart").tag(Int?.some(ACMode.auto.rawValue))
                            Text("Cool").tag(Int?.some(ACMode.cool.rawValue))
                            if heatSupported { Text("Heat").tag(Int?.some(ACMode.heat.rawValue)) }
                            Text("Dry").tag(Int?.some(ACMode.dry.rawValue))
                            Text("Fan").tag(Int?.some(ACMode.fan.rawValue))
                        }
                        Toggle("Set temperature", isOn: Binding(
                            get: { scene.temp != nil },
                            set: { scene.temp = $0 ? (scene.tempFahrenheit ? 72 : 21) : nil }))
                        if let t = scene.temp {
                            Stepper(value: Binding(get: { t }, set: { scene.temp = $0 }), in: range) {
                                Text("\(t)\(scene.tempFahrenheit ? "°F" : "°C")")
                            }
                        }
                    }

                    Section("Fan & extras") {
                        Picker("Fan", selection: $scene.fan) {
                            Text("Don't change").tag(Int?.none)
                            ForEach([FanSpeed.auto, .quiet, .low, .medium, .high]) { f in
                                Text(f.label).tag(Int?.some(f.rawValue))
                            }
                        }
                        triState("Sleep", $scene.sleep)
                        triState("Eco", $scene.eco)
                        triState("Dimmer", $scene.dimmer)
                    }
                }

                Section {
                    Toggle("When I arrive", isOn: Binding(
                        get: { scene.onArrive == true },
                        set: { scene.onArrive = $0 ? true : nil; if $0 { geo.requestAccess() } }))
                    Toggle("When I leave", isOn: Binding(
                        get: { scene.onLeave == true },
                        set: { scene.onLeave = $0 ? true : nil; if $0 { geo.requestAccess() } }))
                    if scene.onArrive == true || scene.onLeave == true {
                        SceneTriggerLocationRows(location: $scene.triggerLocation)
                    }
                } header: {
                    Text("Run automatically")
                } footer: {
                    Text("Choose Home or a location on the map for this scene. iOS geofencing requires Always location access for background triggers. For schedules, use Shortcuts → Automation → Time of Day → Equinox \"Run Scene\".")
                }

                if store.scenes.contains(where: { $0.id == scene.id }) {
                    Section {
                        Button("Delete scene", role: .destructive) {
                            store.deleteScene(scene)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(scene.name.isEmpty ? "New scene" : scene.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if scene.name.trimmingCharacters(in: .whitespaces).isEmpty { scene.name = "Scene" }
                        store.saveScene(scene)
                        dismiss()
                    }
                }
            }
        }
    }

    private func triState(_ label: String, _ value: Binding<Bool?>) -> some View {
        Picker(label, selection: value) {
            Text("Don't change").tag(Bool?.none)
            Text("On").tag(Bool?.some(true))
            Text("Off").tag(Bool?.some(false))
        }
    }
}

struct SceneTriggerLocationRows: View {
    @Binding var location: SceneLocation?
    @ObservedObject private var geo = Geo.shared
    @State private var showingMap = false

    var body: some View {
        if let custom = location {
            LabeledContent("Trigger location", value: "Map pin")
            Text(String(format: "%.4f, %.4f", custom.lat, custom.lon))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Picker("Trigger distance", selection: Binding(
                get: { location?.radius ?? 300 },
                set: { newRadius in
                    guard var point = location else { return }
                    point.radius = newRadius
                    location = point
                })) {
                Text("150 m").tag(150.0)
                Text("300 m").tag(300.0)
                Text("500 m").tag(500.0)
                Text("1 km").tag(1000.0)
                Text("2 km").tag(2000.0)
            }
            Button("Use Home instead") { location = nil }
        } else {
            LabeledContent("Trigger location", value: "Home")
            HomeLocationRows()
            if geo.home == nil {
                Text("Set Home or choose a map location to activate this trigger.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
        Button("Choose scene location on map") { showingMap = true }
        .sheet(isPresented: $showingMap) {
            LocationMapPicker(initial: location.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
            } ?? geo.home.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
            }) { coordinate in
                location = SceneLocation(lat: coordinate.latitude, lon: coordinate.longitude,
                                         radius: location?.radius ?? geo.home?.radius ?? 300)
            }
        }
    }
}

struct HomeLocationRows: View {
    @ObservedObject private var geo = Geo.shared
    @State private var radius: Double = 300
    @State private var showingHomeMap = false

    var body: some View {
        if geo.auth == .denied || geo.auth == .restricted || geo.auth == .authorizedWhenInUse {
            VStack(alignment: .leading, spacing: 6) {
                Label(geo.auth == .authorizedWhenInUse
                      ? "Location is \"While Using\". Set it to Always or triggers won't fire in the background."
                      : "Location access is off for Equinox.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
                Button("Open Settings") {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                }
                .font(.footnote)
            }
        }
        if let h = geo.home {
            LabeledContent("Home", value: String(format: "%.4f, %.4f", h.lat, h.lon))
                .font(.footnote)
        }
        Picker("Trigger distance", selection: Binding(
            get: { geo.home?.radius ?? radius },
            set: { radius = $0; geo.setRadius($0) })) {
            Text("150 m").tag(150.0)
            Text("300 m").tag(300.0)
            Text("500 m").tag(500.0)
            Text("1 km").tag(1000.0)
            Text("2 km").tag(2000.0)
        }
        Button {
            geo.setHomeHere(radius: geo.home?.radius ?? radius)
        } label: {
            HStack {
                Text(geo.home == nil ? "Set home to where I am now" : "Reset home to where I am now")
                if geo.locating { Spacer(); ProgressView() }
            }
        }
        Button("Pick Home on map") { showingHomeMap = true }
            .sheet(isPresented: $showingHomeMap) {
                LocationMapPicker(initial: geo.home.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                }) { coordinate in
                    geo.setHome(lat: coordinate.latitude, lon: coordinate.longitude,
                                radius: geo.home?.radius ?? radius)
                }
            }
        if geo.home != nil {
            Button("Clear Home location", role: .destructive) { geo.clearHome() }
        }
        if let e = geo.lastEvent {
            Text("Last trigger: \(e)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
