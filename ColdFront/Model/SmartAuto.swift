import Foundation

/// Thermostat-style auto: ColdFront watches the room temperature and flips the unit
/// between Cool and Heat (or Fan on cool-only units) around one setpoint, like a home HVAC.
struct SmartAuto: Codable, Equatable {
    var enabled: Bool
    var setpoint: Int
    var fahrenheit: Bool
    var lastSwitch: Date?

    enum Phase: String { case cooling, heating, idle }

    /// Room has to drift this far past the setpoint before the mode flips (hysteresis).
    func deadband(fahrenheit f: Bool) -> Int { f ? 2 : 1 }

    /// Minimum time between cool/heat flips, protects the compressor and stops flapping.
    static let minSwitchInterval: TimeInterval = 5 * 60

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

    /// Properties to send so the unit matches what Smart Auto wants right now, or nil if it already does.
    /// `force` skips the anti-flap timer (used when the user just turned Smart Auto on or changed power).
    func command(for a: Appliance, force: Bool, now: Date = Date()) -> [String: Int]? {
        guard enabled, a.online, a.isOn else { return nil }
        let set = target(for: a)
        let band = deadband(fahrenheit: a.fahrenheit)
        let idleMode: ACMode = a.heatSupported ? .heat : .fan
        let smartModes: Set<ACMode> = a.heatSupported ? [.cool, .heat] : [.cool, .fan]

        let desired: ACMode
        if let room = a.indoorTemp {
            if room >= set + band {
                desired = .cool
            } else if room <= set - band {
                desired = idleMode
            } else if smartModes.contains(a.mode) {
                desired = a.mode            // inside the deadband: hold whatever is running
            } else {
                desired = room >= set ? .cool : idleMode
            }
        } else {
            // No room reading: hold current smart mode, default to cool.
            desired = smartModes.contains(a.mode) ? a.mode : .cool
        }

        var props: [String: Int] = [:]
        if desired != a.mode {
            let tooSoon = lastSwitch.map { now.timeIntervalSince($0) < Self.minSwitchInterval } ?? false
            if force || !tooSoon || !smartModes.contains(a.mode) {
                props[P.mode] = desired.rawValue
            }
        }
        let finalMode = props[P.mode].flatMap(ACMode.init(rawValue:)) ?? a.mode
        if finalMode.allowsTemperature, a.targetTemp != set {
            props[P.target] = set
        }
        return props.isEmpty ? nil : props
    }
}

enum SmartAutoStore {
    private static let key = "smartAuto.v1"

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
