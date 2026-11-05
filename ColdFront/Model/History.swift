import Foundation

/// Rolling 7-day temperature log, one sample per minute per AC, recorded whenever Equinox polls
/// (foreground every 20 s, plus iOS background refreshes). ConnectLife keeps no temperature history,
/// so anything before the app was open simply isn't there.
@MainActor
final class History: ObservableObject {
    static let shared = History()

    struct Sample: Codable, Identifiable {
        var t: Date
        var ac: Double?       // AC's own sensor
        var govee: Double?    // linked Govee, if fresh
        var set: Double?      // setpoint (Smart Auto's target when Auto is on)
        var mode: Int?        // ACMode raw value, nil when off
        var id: Date { t }
    }

    @Published private(set) var log: [String: [Sample]] = [:]
    private let keep: TimeInterval = 7 * 24 * 3600
    private var lastSave = Date.distantPast
    private var lastShared = Date.distantPast

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    init() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: [Sample]].self, from: data) {
            log = decoded
        }
    }

    func record(_ store: Store) {
        let now = Date()
        for a in store.appliances where a.isAirConditioner {
            var list = log[a.id] ?? []
            if let last = list.last, now.timeIntervalSince(last.t) < 55 { continue }
            let g = Govee.shared.reading(for: a.id).flatMap { r -> Double? in
                guard r.isFresh else { return nil }
                return a.fahrenheit ? r.tempC * 9 / 5 + 32 : r.tempC
            }
            let setpoint: Double? = {
                guard a.isOn else { return nil }
                if let s = store.smartAuto(a) { return Double(s.target(for: a)) }
                return a.mode.allowsTemperature ? a.targetTemp.map(Double.init) : nil
            }()
            list.append(Sample(t: now, ac: a.indoorTemp.map(Double.init), govee: g, set: setpoint,
                               mode: a.isOn ? a.mode.rawValue : nil))
            list.removeAll { now.timeIntervalSince($0.t) > keep }
            log[a.id] = list
        }
        if now.timeIntervalSince(lastSave) > 300 { save() }
        if now.timeIntervalSince(lastShared) > 240 { publishShared() }
    }

    /// Last 12 h per AC, bucketed small, for the widgets' graph (they can't read the app's own files).
    func publishShared() {
        lastShared = Date()
        let end = Date(), start = end.addingTimeInterval(-12 * 3600)
        var out: [String: ACHistoryWire] = [:]
        for (id, list) in log {
            let recent = list.filter { $0.t >= start }
            let room = recent.compactMap { s in (s.govee ?? s.ac).map { TempPoint(t: s.t, v: $0) } }
            var set: [TempPoint] = []
            var last: Double?
            for s in recent {
                guard let v = s.set, v != last else { continue }
                set.append(TempPoint(t: s.t, v: v)); last = v
            }
            out[id] = ACHistoryWire(room: TempSeries.bucket(room, from: start, to: end, step: 15 * 60), set: set)
        }
        AppGroup.write(out, ACHistoryWire.file)
    }

    func save() {
        lastSave = Date()
        if let data = try? JSONEncoder().encode(log) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func samples(_ id: String, since: Date) -> [Sample] {
        (log[id] ?? []).filter { $0.t >= since }
    }
}
