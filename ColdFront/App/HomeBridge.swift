import Foundation
import Network
import SwiftUI

/// the Keystone Bridge (ESP32) puts devices in Apple Home. Equinox pairs with it on its own token and
/// sends the ConnectLife login and the AC's id. The bridge talks to ConnectLife itself after that and
/// runs Smart Auto, so the AC works from Home and keeps its thermostat behaviour with this phone away.
struct HomeBridgeLink: Codable, Equatable {
    var host = ""
    var port = 8080
    var token = ""
    var lastSent: Date?

    var isSet: Bool { !host.isEmpty && !token.isEmpty }

    static var stored: HomeBridgeLink {
        get {
            guard let d = UserDefaults.standard.data(forKey: "homeBridge"),
                  let v = try? JSONDecoder().decode(HomeBridgeLink.self, from: d) else { return HomeBridgeLink() }
            return v
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "homeBridge") }
    }
}

enum HomeBridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}

enum HomeBridgeAPI {
    static let app = "equinox"

    static func url(_ host: String, _ port: Int, _ path: String) -> URL? { URL(string: "http://\(host):\(port)\(path)") }

    static func info(host: String, port: Int) async throws -> [String: Any] {
        guard let u = url(host, port, "/api/info") else { throw HomeBridgeError.message("Bad address.") }
        var req = URLRequest(url: u)
        req.timeoutInterval = 4
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["app"] as? String == "afterglow-bridge" else { throw HomeBridgeError.message("That isn't a Keystone Bridge.") }
        return obj
    }

    static func claim(host: String, port: Int) async throws -> String {
        guard let u = url(host, port, "/api/dev/claim?app=\(app)") else { throw HomeBridgeError.message("Bad address.") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        let (data, resp) = try await URLSession.shared.data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 409 {
            throw HomeBridgeError.message("The bridge is already paired with Equinox on another install. In Keystone › Bridge, tap Reset next to Equinox, then pair here again.")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let t = obj["token"] as? String else {
            throw HomeBridgeError.message("The bridge didn't hand out a token. Update its firmware from Afterglow.")
        }
        return t
    }

    /// True when the bridge restarts to add the device to Home.
    static func send(_ body: [String: Any], _ link: HomeBridgeLink) async throws -> Bool {
        guard let u = url(link.host, link.port, "/api/dev/config?app=\(app)") else { throw HomeBridgeError.message("Bad address.") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(link.token, forHTTPHeaderField: "X-Device-Token")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw HomeBridgeError.message("The bridge doesn't know this phone anymore. Forget it here and pair again.") }
        guard code == 200, let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HomeBridgeError.message("Bridge said: \(String(decoding: data, as: UTF8.self))")
        }
        return obj["restart"] as? Bool ?? false
    }
}

/// Finds bridges by Bonjour (_afterglow._tcp).
@MainActor
final class HomeBridgeFinder: ObservableObject {
    struct Found: Hashable { var name: String; var host: String; var port: Int }
    @Published var found: [Found] = []
    @Published var searching = false
    private var browser: NWBrowser?

    func start() {
        stop()
        searching = true
        found = []
        let b = NWBrowser(for: .bonjour(type: "_afterglow._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            for r in results {
                guard case .service(let name, _, _, _) = r.endpoint else { continue }
                Task { await self?.resolve(r.endpoint, name: name) }
            }
        }
        b.start(queue: .main)
        browser = b
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            searching = false
        }
    }

    func stop() {
        browser?.cancel()
        browser = nil
        searching = false
    }

    private func resolve(_ endpoint: NWEndpoint, name: String) async {
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let c = NWConnection(to: endpoint, using: params)
        let result: (String, Int)? = await withCheckedContinuation { cont in
            let once = OnceFlag()
            c.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let h, let p)? = c.currentPath?.remoteEndpoint, once.fire() {
                        var host = "\(h)"
                        if let pct = host.firstIndex(of: "%") { host = String(host[..<pct]) }
                        cont.resume(returning: (host, Int(p.rawValue)))
                    } else if once.fire() { cont.resume(returning: nil) }
                    c.cancel()
                case .failed, .cancelled:
                    if once.fire() { cont.resume(returning: nil) }
                default: break
                }
            }
            c.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                if once.fire() { cont.resume(returning: nil); c.cancel() }
            }
        }
        guard let r = result, !found.contains(where: { $0.host == r.0 }) else { return }
        found.append(Found(name: name, host: r.0, port: r.1))
    }
}

final class OnceFlag: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func fire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

// MARK: - What Equinox sends

extension Store {
    /// True once the AC is on the bridge: the bridge then owns Smart Auto, so the app stops deciding itself.
    var bridgeOwnsAuto: Bool { HomeBridgeLink.stored.isSet && HomeBridgeLink.stored.lastSent != nil }

    func homeBridgeConfig() -> (body: [String: Any]?, problem: String?) {
        guard let creds = Keychain.load() else { return (nil, "Sign in to ConnectLife first.") }
        guard let a = appliances.first(where: \.isAirConditioner) else { return (nil, "No air conditioner found in your ConnectLife account yet. Pull to refresh on the main screen.") }
        var auto: [String: Any] = ["enabled": false, "setpoint": 21.0, "band": 3.0]
        if let s = smart[a.id] {
            let setC = s.fahrenheit ? (Double(s.setpoint) - 32) * 5 / 9 : Double(s.setpoint)
            let b = Double(s.band ?? SmartAuto.defaultBand(fahrenheit: s.fahrenheit))
            auto = ["enabled": s.enabled, "setpoint": (setC * 2).rounded() / 2, "band": max(0.5, s.fahrenheit ? b * 5 / 9 : b)]
        }
        return (["utcOffset": TimeZone.current.secondsFromGMT(),
                 "ac": ["user": creds.user, "pass": creds.pass, "puid": a.puid, "name": a.name,
                        "heat": a.heatSupported, "auto": auto]], nil)
    }

    /// The other way round: Smart Auto changed in Keystone (or on the bridge) shows up here too.
    func syncSmartAutoFromBridge() async {
        let l = HomeBridgeLink.stored
        // A change made here wins: don't read the bridge back until it has surely received it.
        guard Date().timeIntervalSince(HomeBridgeSync.localChangeAt) > 20 else { return }
        guard bridgeOwnsAuto, let a = appliances.first(where: \.isAirConditioner),
              let info = try? await HomeBridgeAPI.info(host: l.host, port: l.port),
              let ac = info["ac"] as? [String: Any], let au = ac["auto"] as? [String: Any],
              let en = au["enabled"] as? Bool,
              let sp = (au["setpoint"] as? NSNumber)?.doubleValue,
              let band = (au["band"] as? NSNumber)?.doubleValue else { return }
        var s = smart[a.id] ?? SmartAuto(enabled: false, setpoint: 21, fahrenheit: a.fahrenheit)
        let f = s.fahrenheit
        let spU = f ? Int((sp * 9 / 5 + 32).rounded()) : Int(sp.rounded())
        let bU = max(1, Int((f ? band * 9 / 5 : band).rounded()))
        guard s.enabled != en || s.setpoint != spU || (s.band ?? SmartAuto.defaultBand(fahrenheit: f)) != bU else { return }
        s.enabled = en; s.setpoint = spU; s.band = bU
        HomeBridgeSync.suppressPush = true
        smart[a.id] = s
        HomeBridgeSync.suppressPush = false
    }

    /// Keep the bridge's Smart Auto in step with the app (setpoint, band, on/off). Debounced.
    func pushSmartAutoToBridge() {
        guard bridgeOwnsAuto, !HomeBridgeSync.suppressPush else { return }
        HomeBridgeSync.localChangeAt = Date()
        HomeBridgeSync.schedule { [weak self] in
            guard let body = self?.homeBridgeConfig().body else { return }
            _ = try? await HomeBridgeAPI.send(body, HomeBridgeLink.stored)
        }
    }
}

@MainActor
enum HomeBridgeSync {
    private static var task: Task<Void, Never>?
    static var suppressPush = false
    static var localChangeAt = Date.distantPast
    static func schedule(_ work: @escaping () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            await work()
        }
    }
}

// MARK: - Screen

struct HomeBridgeView: View {
    @EnvironmentObject var store: Store
    @StateObject private var finder = HomeBridgeFinder()
    @State private var link = HomeBridgeLink.stored
    @State private var status: String?
    @State private var busy = false
    @State private var manualHost = ""
    @State private var bridgeAC: [String: Any]?

    var body: some View {
        Form {
            Section {
                Text("The Keystone Bridge (ESP32) can put the AC in Apple Home as a proper thermostat tile, and run Smart Auto itself around the clock: it switches between cool and heat around your setpoint using the Govee reading, with this phone off or away. Equinox hands it your ConnectLife login so it can talk to the AC directly.")
                    .font(.footnote)
            }

            if link.isSet {
                Section {
                    LabeledContent("Bridge", value: link.host)
                    if let d = link.lastSent { LabeledContent("Last sent", value: d.formatted(date: .abbreviated, time: .shortened)) }
                    if let a = bridgeAC {
                        LabeledContent("AC on the bridge", value: (a["ok"] as? Bool) == true ? "talking to ConnectLife" : ((a["error"] as? String) ?? "starting…"))
                        if let auto = a["auto"] as? [String: Any], (auto["enabled"] as? Bool) == true {
                            LabeledContent("Smart Auto", value: String(format: "%.1f° ± %.1f°", (auto["setpoint"] as? Double) ?? 0, (auto["band"] as? Double) ?? 0))
                        }
                        if let r = a["room"] as? Double { LabeledContent("Room (bridge)", value: String(format: "%.1f°C", r)) }
                    }
                    Button { Task { await send() } } label: {
                        Label(busy ? "Sending…" : "Send AC to Apple Home", systemImage: "arrow.up.circle")
                    }
                    .disabled(busy)
                    Button("Stop using the bridge", role: .destructive) {
                        link = HomeBridgeLink()
                        HomeBridgeLink.stored = link
                        finder.start()
                    }
                } footer: {
                    Text("While the bridge has the AC, Smart Auto runs there and Equinox just sends it your changes. The first send restarts the bridge (about 20 s) so Home sees the new tile. Remove the Matter copy of the AC from Home if you don't want two tiles.")
                }
            } else {
                Section {
                    if finder.searching { HStack { ProgressView(); Text("Looking for the bridge…") } }
                    ForEach(finder.found, id: \.self) { f in
                        Button { Task { await pair(f.host, f.port) } } label: { LabeledContent(f.name, value: f.host) }
                    }
                    Button("Search again") { finder.start() }
                    HStack {
                        TextField("Or type its IP", text: $manualHost).keyboardType(.decimalPad)
                        Button("Pair") { Task { await pair(manualHost.trimmingCharacters(in: .whitespaces), 8080) } }
                            .disabled(manualHost.isEmpty)
                    }
                } header: {
                    Text("Pair")
                } footer: {
                    Text("Needs bridge firmware 1.5 or newer. Update it from the Keystone app (Bridge › Firmware).")
                }
            }
            if let status { Section { Text(status).font(.footnote) } }
        }
        .navigationTitle("Keystone Bridge")
        .onAppear {
            link = HomeBridgeLink.stored
            if !link.isSet { finder.start() } else { Task { await loadInfo() } }
        }
        .onDisappear { finder.stop() }
    }

    private func loadInfo() async {
        guard let info = try? await HomeBridgeAPI.info(host: link.host, port: link.port) else { return }
        bridgeAC = info["ac"] as? [String: Any]
    }

    private func pair(_ host: String, _ port: Int) async {
        guard !host.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let info = try await HomeBridgeAPI.info(host: host, port: port)
            guard info["ac"] != nil else {
                status = "This bridge's firmware is too old for the AC. Update it from Keystone (Bridge › Firmware), then pair here."
                return
            }
            let token = try await HomeBridgeAPI.claim(host: host, port: port)
            link = HomeBridgeLink(host: host, port: port, token: token)
            HomeBridgeLink.stored = link
            busy = false
            await send()
        } catch {
            status = "Couldn't pair: \(error.localizedDescription)"
        }
    }

    private func send() async {
        let built = store.homeBridgeConfig()
        guard let body = built.body else { status = built.problem; return }
        busy = true
        defer { busy = false }
        do {
            let restart = try await HomeBridgeAPI.send(body, link)
            link.lastSent = .now
            HomeBridgeLink.stored = link
            status = restart ? "Sent. The bridge is restarting to add the AC to Apple Home (about 20 s). It shows up under the bridge; no new pairing needed."
                             : "Sent. The bridge is up to date."
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await loadInfo()
        } catch {
            status = error.localizedDescription
        }
    }
}
