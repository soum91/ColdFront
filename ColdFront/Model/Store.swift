import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published var appliances: [Appliance] = []
    @Published var loggedIn = false
    @Published var busy = false
    @Published var error: String?
    @Published var lastUpdated: Date?

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
        } catch {
            self.error = error.localizedDescription
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

    // MARK: Convenience commands

    func setPower(_ a: Appliance, _ on: Bool) {
        var p = [P.power: on ? 1 : 0]
        if on, let t = a.targetTemp { p[P.target] = t }
        send(a.id, p)
    }

    func setMode(_ a: Appliance, _ m: ACMode) {
        var p = [P.power: 1, P.mode: m.rawValue]
        if m.allowsTemperature, let t = a.targetTemp { p[P.target] = t }
        send(a.id, p)
    }

    func setTemp(_ a: Appliance, _ t: Int) {
        send(a.id, [P.target: min(max(t, a.tempRange.lowerBound), a.tempRange.upperBound)])
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
        send(a.id, p)
    }

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
