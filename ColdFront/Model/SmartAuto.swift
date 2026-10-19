import Foundation

/// Thermostat-style auto: ColdFront flips the unit between Cool and Heat (Fan on cool-only units)
/// around one setpoint. The unit's own thermostat does the fine control inside each mode;
/// ColdFront only changes mode when the room is well outside the band, and it changes it rarely.
///
/// Every command makes the unit beep and wake its display, so this is deliberately lazy:
/// it never re-sends something it already sent, it waits for a reading to hold before acting,
/// and it enforces a long minimum time in each mode to protect the compressor.
struct SmartAuto: Codable, Equatable {
    var enabled: Bool
    var setpoint: Int
    var fahrenheit: Bool
    var lastSwitch: Date?

    /// Degrees past the setpoint before a mode flip, in the setpoint's unit. Default 3 °C / 5 °F.
    var band: Int?
    /// Mode the room is asking for, and when it started asking (must hold before we act).
    var pendingMode: Int?
    var pendingSince: Date?
    /// Last command ColdFront sent, so it is never repeated.
    var lastSentMode: Int?
    var lastSentTarget: Int?

    enum Phase: String { case cooling, heating, idle }

    /// Minimum time in a mode before ColdFront will flip it again.
    static let minDwell: TimeInterval = 30 * 60
    /// The room must stay out of band this long before a flip (filters sensor noise and door openings).
    static let confirmFor: TimeInterval = 5 * 60

    static func defaultBand(fahrenheit: Bool) -> Int { fahrenheit ? 5 : 3 }

    /// Band in the device's current unit.
    func band(for a: Appliance) -> Int {
        let b = band ?? Self.defaultBand(fahrenheit: fahrenheit)
        guard fahrenheit != a.fahrenheit else { return b }
        return max(1, a.fahrenheit ? Int((Double(b) * 9 / 5).rounded()) : Int((Double(b) * 5 / 9).rounded()))
    }

    /// Setpoint expressed in the unit the device is currently using.
    func target(for a: Appliance) -> Int {
        guard fahrenheit != a.fahrenheit else { return setpoint }
        return a.fahrenheit
            ? Int((Double(setpoint) * 9 / 5 + 32).rounded())
            : Int(((Double(setpoint) - 32) * 5 / 9).rounded())
    }

    func phase(of a: Appliance) -> Phase {
        switch a.mode {
        case .cool: return .cooling
        case .heat: return .heating
        default: return .idle
        }
    }

    /// Work out what (if anything) to send. Returns the props plus the updated state to store.
    /// `userAction` is true when the person just tapped Auto, changed the setpoint or powered on:
    /// that bypasses the confirm/dwell timers, because they asked for it.
    func decide(for a: Appliance, room: Double?, userAction: Bool, now: Date = Date()) -> (props: [String: Int], state: SmartAuto) {
        var s = self
        guard enabled, a.online, a.isOn else { return ([:], s) }

        let set = target(for: a)
        let band = band(for: a)
        let idleMode: ACMode = a.heatSupported ? .heat : .fan
        let smartModes: Set<ACMode> = a.heatSupported ? [.cool, .heat] : [.cool, .fan]
        let inSmartMode = smartModes.contains(a.mode)

        // What the room is asking for.
        var wanted: ACMode = inSmartMode ? a.mode : .cool
        if let room {
            if room >= Double(set + band) {
                wanted = .cool
            } else if room <= Double(set - band) {
                wanted = idleMode
            } else if !inSmartMode {
                wanted = room >= Double(set) ? .cool : idleMode
            }
        }

        var props: [String: Int] = [:]

        if wanted != a.mode {
            if userAction || !inSmartMode {
                props[P.mode] = wanted.rawValue
            } else {
                // Require the reading to hold, and respect the minimum time in the current mode.
                if s.pendingMode != wanted.rawValue {
                    s.pendingMode = wanted.rawValue
                    s.pendingSince = now
                }
                let held = now.timeIntervalSince(s.pendingSince ?? now) >= Self.confirmFor
                let dwellOK = s.lastSwitch.map { now.timeIntervalSince($0) >= Self.minDwell } ?? true
                if held && dwellOK { props[P.mode] = wanted.rawValue }
            }
        } else {
            s.pendingMode = nil
            s.pendingSince = nil
        }

        let finalMode = props[P.mode].flatMap(ACMode.init(rawValue:)) ?? a.mode

        // Only send the setpoint when the mode changes or the person changed it, and never
        // the same value twice. Stops a mismatch in the reported value from spamming the unit.
        if finalMode.allowsTemperature, a.targetTemp != set {
            let modeChanging = props[P.mode] != nil
            if modeChanging || userAction || s.lastSentTarget != set {
                props[P.target] = set
            }
        }

        // Never re-send an identical command.
        if !userAction, props[P.mode] == nil, let t = props[P.target], t == s.lastSentTarget {
            props[P.target] = nil
        }

        if let m = props[P.mode] {
            s.lastSwitch = now
            s.lastSentMode = m
            s.pendingMode = nil
            s.pendingSince = nil
        }
        if let t = props[P.target] { s.lastSentTarget = t }
        return (props, s)
    }
}

enum SmartAutoStore {
    private static let key = "smartAuto.v2"

    static func load() -> [String: SmartAuto] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: SmartAuto].self, from: data) else { return [:] }
        return dict
    }

    static func save(_ dict: [String: SmartAuto]) {
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
