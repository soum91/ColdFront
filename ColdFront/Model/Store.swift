import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var appliances: [Appliance] = []
    @Published var loggedIn = false
    @Published var busy = false
    @Published var error: String?
    @Published var lastUpdated: Date?
    @Published var smart: [String: SmartAuto] = SmartAutoStore.load() {
        didSet { SmartAutoStore.save(smart) }
    }
    @Published var scenes: [ACScene] = ScenesStore.load() {
        didSet { ScenesStore.save(scenes) }
    }

    private var client: ConnectLifeClient?
    private var pollTask: Task<Void, Never>?
    /// Suppress poll overwrites for a few seconds after a command so the UI doesn't snap back.
    private var pendingUntil: [String: Date] = [:]

    init() {
        if let creds = Keychain.load() {
            client = ConnectLifeClient(username: creds.user, password: creds.pass)
            loggedIn = true
        }
    }

    var savedUsername: String { Keychain.load()?.user ?? "" }

    func login(user: String, pass: String) async {
        busy = true; error = nil
        defer { busy = false }
        let c = ConnectLifeClient(username: user, password: pass)
        do {
            try await c.login()
            Keychain.save(user: user, pass: pass)
            client = c
            loggedIn = true
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func logout() {
        stopPolling()
        Keychain.clear()
        client = nil
        appliances = []
        loggedIn = false
    }

    func refresh() async {
        guard let client else { return }
        do {
            var fresh = try await client.appliances()
            let now = Date()
            // Keep optimistic values for devices with a command in flight.
            for i in fresh.indices {
                if let until = pendingUntil[fresh[i].id], until > now,
                   let local = appliances.first(where: { $0.id == fresh[i].id }) {
                    fresh[i].status = local.status
                }
            }
            appliances = fresh
            lastUpdated = now
            error = nil
            runSmartAuto()
            History.shared.record(self)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Background app refresh: poll once and apply Smart Auto, awaiting the writes so iOS doesn't suspend us mid-request.
    func backgroundTick() async {
        guard let client else { return }
        guard let fresh = try? await client.appliances() else { return }
        appliances = fresh
        lastUpdated = Date()
        History.shared.record(self)
        defer { History.shared.save() }
        for a in fresh {
            guard let st = smartAuto(a) else { continue }
            let (cmd, next) = st.decide(for: a, room: roomTemp(a).value, userAction: false)
            if next != st { smart[a.id] = next }
            if !cmd.isEmpty {
                try? await client.set(puid: a.puid, properties: cmd.mapValues(String.init))
            }
        }
    }

    func startPolling(every seconds: Double = 20) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func appliance(_ id: String) -> Appliance? { appliances.first { $0.id == id } }

    /// Send properties, update the UI immediately, roll back on failure.
    func send(_ id: String, _ props: [String: Int]) {
        guard let client, let idx = appliances.firstIndex(where: { $0.id == id }) else { return }
        let before = appliances[idx]
        for (k, v) in props { appliances[idx].status[k] = String(v) }
        pendingUntil[id] = Date().addingTimeInterval(8)
        let puid = before.puid
        let strings = props.mapValues(String.init)
        Task {
            do {
                try await client.set(puid: puid, properties: strings)
            } catch {
                if let i = appliances.firstIndex(where: { $0.id == id }) { appliances[i] = before }
                pendingUntil[id] = nil
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: Smart Auto

    enum RoomSource { case govee, ac, none }

    /// Room temperature Auto should act on, in the device's unit: the linked Govee when its
    /// reading is under 5 minutes old (and not switched off for this AC), otherwise the AC's own sensor.
    func roomTemp(_ a: Appliance) -> (value: Double?, source: RoomSource) {
        let g = Govee.shared
        if g.acOnly[a.id] != true, let r = g.reading(for: a.id), r.isFresh {
            return (a.fahrenheit ? r.tempC * 9 / 5 + 32 : r.tempC, .govee)
        }
        if let t = a.indoorTemp { return (Double(t), .ac) }
        return (nil, .none)
    }

    func smartAuto(_ a: Appliance) -> SmartAuto? {
        guard let s = smart[a.id], s.enabled else { return nil }
        return s
    }

    /// Setpoint the dial should show: Smart Auto's own target when it's on, otherwise the unit's.
    func displayedTarget(_ a: Appliance) -> Int? {
        smartAuto(a)?.target(for: a) ?? a.targetTemp
    }

    func enableSmartAuto(_ a: Appliance) {
        let seed = a.targetTemp.flatMap { a.mode.allowsTemperature ? $0 : nil }
            ?? (a.fahrenheit ? 72 : 22)
        let keepBand = smart[a.id]?.band
        smart[a.id] = SmartAuto(enabled: true, setpoint: seed, fahrenheit: a.fahrenheit, lastSwitch: nil, band: keepBand)
        var cur = a
        cur.status[P.power] = "1"
        applySmart(cur, userAction: true, extra: a.isOn ? [:] : [P.power: 1])
    }

    func disableSmartAuto(_ id: String) {
        smart[id]?.enabled = false
    }

    /// Switch band (degrees past the setpoint before Auto flips mode), in the device's current unit.
    func setBand(_ a: Appliance, _ b: Int) {
        guard var s = smart[a.id] else { return }
        let inSetpointUnit = s.fahrenheit == a.fahrenheit ? b
            : (s.fahrenheit ? Int((Double(b) * 9 / 5).rounded()) : Int((Double(b) * 5 / 9).rounded()))
        s.band = max(1, inSetpointUnit)
        smart[a.id] = s
    }

    /// Called after every poll.
    func runSmartAuto() {
        for a in appliances where smartAuto(a) != nil {
            applySmart(a, userAction: false)
        }
    }

    private func applySmart(_ a: Appliance, userAction: Bool, extra: [String: Int] = [:]) {
        guard let st = smartAuto(a) else { return }
        let (props, next) = st.decide(for: a, room: roomTemp(a).value, userAction: userAction)
        if next != st { smart[a.id] = next }
        let cmd = props.merging(extra) { $1 }
        if !cmd.isEmpty { send(a.id, cmd) }
    }

    // MARK: Convenience commands

    func setPower(_ a: Appliance, _ on: Bool) {
        if on, smartAuto(a) != nil {
            var cur = a
            cur.status[P.power] = "1"
            applySmart(cur, userAction: true, extra: [P.power: 1])
            return
        }
        var p = [P.power: on ? 1 : 0]
        if on, a.mode.allowsTemperature, let t = a.targetTemp { p[P.target] = t }
        send(a.id, p)
    }

    func setMode(_ a: Appliance, _ m: ACMode) {
        if m == .auto {
            enableSmartAuto(a)
            return
        }
        disableSmartAuto(a.id)
        var p = [P.power: 1, P.mode: m.rawValue]
        if m.allowsTemperature, let t = a.targetTemp { p[P.target] = t }
        send(a.id, p)
    }

    func setTemp(_ a: Appliance, _ t: Int) {
        let clamped = min(max(t, a.tempRange.lowerBound), a.tempRange.upperBound)
        if var s = smartAuto(a) {
            s.setpoint = clamped
            s.fahrenheit = a.fahrenheit
            smart[a.id] = s
            applySmart(a, userAction: true)
            return
        }
        send(a.id, [P.target: clamped])
    }

    func setFan(_ a: Appliance, _ f: FanSpeed) { send(a.id, [P.fan: f.rawValue]) }

    func toggle(_ a: Appliance, _ key: String) { send(a.id, [key: a.flag(key) ? 0 : 1]) }

    func setUnit(_ a: Appliance, fahrenheit: Bool) {
        guard fahrenheit != a.fahrenheit else { return }
        var p = [P.unit: fahrenheit ? 1 : 0]
        if let t = a.targetTemp {
            let converted = fahrenheit ? Int((Double(t) * 9 / 5 + 32).rounded()) : Int(((Double(t) - 32) * 5 / 9).rounded())
            p[P.target] = converted
        }
        if var s = smartAuto(a) {
            var asDevice = a
            asDevice.status[P.unit] = fahrenheit ? "1" : "0"
            s.setpoint = s.target(for: asDevice)
            s.fahrenheit = fahrenheit
            smart[a.id] = s
        }
        send(a.id, p)
    }

    // MARK: Scenes

    /// Send and wait for the server to accept (used by scenes and Shortcuts, where the process may be suspended right after).
    func commit(_ id: String, _ props: [String: Int]) async throws {
        guard let client, let idx = appliances.firstIndex(where: { $0.id == id }) else {
            throw ConnectLifeClient.ClientError.unexpected("Not signed in")
        }
        let before = appliances[idx]
        for (k, v) in props { appliances[idx].status[k] = String(v) }
        pendingUntil[id] = Date().addingTimeInterval(8)
        do {
            try await client.set(puid: before.puid, properties: props.mapValues(String.init))
        } catch {
            if let i = appliances.firstIndex(where: { $0.id == id }) { appliances[i] = before }
            pendingUntil[id] = nil
            self.error = error.localizedDescription
            throw error
        }
    }

    /// Apply a scene to every online AC on the account.
    func runScene(_ scene: ACScene) async throws {
        if appliances.isEmpty { await refresh() }
        let targets = appliances.filter { $0.isAirConditioner && $0.online }
        guard !targets.isEmpty else { throw ConnectLifeClient.ClientError.unexpected("No online air conditioner") }
        for a in targets {
            let props = sceneProps(scene, a)
            if !props.isEmpty { try await commit(a.id, props) }
        }
    }

    private func sceneProps(_ s: ACScene, _ a: Appliance) -> [String: Int] {
        guard s.power else { return [P.power: 0] }
        var p: [String: Int] = [P.power: 1]
        let temp: Int? = s.temp.map { t in
            let v = s.tempFahrenheit == a.fahrenheit ? t
                : (a.fahrenheit ? Int((Double(t) * 9 / 5 + 32).rounded()) : Int(((Double(t) - 32) * 5 / 9).rounded()))
            return min(max(v, a.tempRange.lowerBound), a.tempRange.upperBound)
        }
        var on = a
        on.status[P.power] = "1"

        func runSmart(_ st: SmartAuto) {
            let (props, next) = st.decide(for: on, room: roomTemp(a).value, userAction: true)
            smart[a.id] = next
            p.merge(props) { $1 }
        }

        if let m = s.acMode {
            if m == .auto {
                var st = smart[a.id] ?? SmartAuto(enabled: true, setpoint: temp ?? a.targetTemp ?? (a.fahrenheit ? 72 : 22),
                                                 fahrenheit: a.fahrenheit, lastSwitch: nil)
                st.enabled = true
                if let temp { st.setpoint = temp; st.fahrenheit = a.fahrenheit }
                runSmart(st)
            } else {
                disableSmartAuto(a.id)
                p[P.mode] = m.rawValue
                if m.allowsTemperature, let t = temp ?? a.targetTemp { p[P.target] = t }
            }
        } else if var st = smartAuto(a) {
            if let temp { st.setpoint = temp; st.fahrenheit = a.fahrenheit }
            runSmart(st)
        } else if let temp, a.mode.allowsTemperature {
            p[P.target] = temp
        }

        if let f = s.fan { p[P.fan] = f }
        for (key, value) in [(P.sleep, s.sleep), (P.eco, s.eco), (P.dimmer, s.dimmer)] {
            if let v = value, a.has(key) { p[key] = v ? 1 : 0 }
        }
        return p
    }

    func saveScene(_ s: ACScene) {
        if let i = scenes.firstIndex(where: { $0.id == s.id }) { scenes[i] = s } else { scenes.append(s) }
    }

    func deleteScene(_ s: ACScene) { scenes.removeAll { $0.id == s.id } }

    func energy(_ a: Appliance, stat: String) async -> (Double?, [String: Double]) {
        guard let client else { return (nil, [:]) }
        do {
            let r = try await client.energy(for: a, stat: stat)
            return (r.total, r.curve)
        } catch {
            return (nil, [:])
        }
    }
}
