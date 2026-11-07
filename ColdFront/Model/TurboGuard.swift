import Foundation

/// Manual Turbo auto-off: when Turbo is switched on by hand (app, remote or the unit's panel),
/// Equinox switches it back off once the room gets within 3 °C (5 °F) of the set temperature,
/// in Cool or Heat. Smart Auto's own startup boost is left alone (it has its own exit rule).
///
/// If Turbo is switched on when the room is already within 3 °C, it runs until the set
/// temperature itself is reached instead, so it doesn't switch straight back off.
struct TurboWatch: Codable, Equatable {
    var mode: Int
    var offset: Double         // degrees short of the set temp at which Turbo stops
    var armedAt: Date
    var offSentAt: Date?
}

enum TurboGuardStore {
    private static let key = "turboWatch.v1"
    static var watches: [String: TurboWatch] = load() {
        didSet {
            if let d = try? JSONEncoder().encode(watches) { UserDefaults.standard.set(d, forKey: key) }
        }
    }
    private static func load() -> [String: TurboWatch] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let w = try? JSONDecoder().decode([String: TurboWatch].self, from: d) else { return [:] }
        return w
    }
}

extension Store {
    static func turboStopGap(fahrenheit: Bool) -> Double { fahrenheit ? 5 : 3 }

    /// Props to send for this AC right now (empty when nothing to do). Updates the watch state.
    func turboGuardCommand(_ a: Appliance, now: Date = Date()) -> [String: Int] {
        let id = a.id
        let smartBoost = smartAuto(a)?.startupTurbo == true
        guard a.isAirConditioner, a.online, a.isOn, a.flag(P.turbo), !smartBoost,
              a.mode == .cool || a.mode == .heat else {
            if !a.flag(P.turbo) || !a.isOn { TurboGuardStore.watches[id] = nil }
            return [:]
        }
        guard let room = roomTemp(a).value, let target = displayedTarget(a) else { return [:] }
        let set = Double(target)
        let gap = Self.turboStopGap(fahrenheit: a.fahrenheit)

        var w = TurboGuardStore.watches[id]
        if w == nil || w?.mode != a.mode.rawValue {
            let distance = a.mode == .cool ? room - set : set - room
            w = TurboWatch(mode: a.mode.rawValue, offset: distance > gap ? gap : 0, armedAt: now)
        }
        guard var watch = w else { return [:] }

        let reached = a.mode == .cool ? room <= set + watch.offset : room >= set - watch.offset
        var props: [String: Int] = [:]
        // Send once; if the unit still reports Turbo three minutes later, try one more time.
        if reached, watch.offSentAt.map({ now.timeIntervalSince($0) > 180 }) ?? true {
            props[P.turbo] = 0
            watch.offSentAt = now
        }
        TurboGuardStore.watches[id] = watch
        return props
    }

    func runTurboGuard() {
        for a in appliances {
            let cmd = turboGuardCommand(a)
            if !cmd.isEmpty { send(a.id, cmd) }
        }
    }

    /// Re-arm from scratch whenever the person flips Turbo themselves.
    func resetTurboGuard(_ id: String) { TurboGuardStore.watches[id] = nil }
}
