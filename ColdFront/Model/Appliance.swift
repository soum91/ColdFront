import Foundation

struct Appliance: Identifiable, Hashable {
    let id: String          // deviceId
    let puid: String
    var name: String
    let typeCode: String
    let featureCode: String
    let typeName: String
    let featureName: String
    let room: String
    var online: Bool
    var status: [String: String]

    init?(json: [String: Any]) {
        guard let deviceId = json["deviceId"] as? String,
              let puid = json["puid"] as? String else { return nil }
        id = deviceId
        self.puid = puid
        name = (json["deviceNickName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Air Conditioner"
        typeCode = "\(json["deviceTypeCode"] ?? "")"
        featureCode = "\(json["deviceFeatureCode"] ?? "")"
        typeName = (json["deviceTypeName"] as? String) ?? ""
        featureName = (json["deviceFeatureName"] as? String) ?? ""
        room = (json["roomName"] as? String) ?? ""
        // offlineState: 1 = online in observed payloads
        online = "\(json["offlineState"] ?? "1")" == "1"
        var s: [String: String] = [:]
        for (k, v) in (json["statusList"] as? [String: Any] ?? [:]) { s[k] = "\(v)" }
        status = s
    }

    func int(_ key: String) -> Int? {
        guard let raw = status[key] else { return nil }
        if let i = Int(raw) { return i }
        if let d = Double(raw) { return Int(d) }
        return nil
    }
    func flag(_ key: String) -> Bool { int(key) == 1 }
    func has(_ key: String) -> Bool { status[key] != nil }

    var isAirConditioner: Bool { ["006", "008", "009"].contains(typeCode) }
    var isPortableAC: Bool { typeCode == "006" }
}

// MARK: - AC semantics (ConnectLife portable AC property map, type 006)

enum ACMode: Int, CaseIterable, Identifiable {
    case fan = 0, heat = 1, cool = 2, dry = 3, auto = 4
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .fan: "Fan"
        case .heat: "Heat"
        case .cool: "Cool"
        case .dry: "Dry"
        case .auto: "Auto"
        }
    }
    var symbol: String {
        switch self {
        case .fan: "fan"
        case .heat: "sun.max"
        case .cool: "snowflake"
        case .dry: "drop"
        case .auto: "a.circle"
        }
    }
    var allowsTemperature: Bool { self == .cool || self == .heat || self == .auto }
}

enum FanSpeed: Int, CaseIterable, Identifiable {
    case auto = 0, low = 2, medium = 3, high = 4, quiet = 5
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .auto: "Auto"
        case .low: "Low"
        case .medium: "Med"
        case .high: "High"
        case .quiet: "Quiet"
        }
    }
    var level: Int {
        switch self {
        case .auto: 0
        case .quiet: 1
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }
}

enum P {
    static let power = "t_power"
    static let mode = "t_work_mode"
    static let target = "t_temp"
    static let unit = "t_temp_type"
    static let indoor = "f_temp_in"
    static let humidity = "f_humidity"
    static let fan = "t_fan_speed"
    static let swing = "t_up_down"
    static let eco = "t_eco"
    static let sleep = "t_sleep"
    static let turbo = "t_super"
    static let mute = "t_fan_mute"
    static let filter = "f-filter"
    static let waterFull = "f_e_waterfull"
    static let watts = "f_power_display"
    static let kwh = "f_power_consumption"
    static let beep = "t_beep"
}

extension Appliance {
    var isOn: Bool { flag(P.power) }
    var mode: ACMode { ACMode(rawValue: int(P.mode) ?? 2) ?? .cool }
    var fan: FanSpeed { FanSpeed(rawValue: int(P.fan) ?? 0) ?? .auto }
    var fahrenheit: Bool { int(P.unit) == 1 }
    var unitSymbol: String { fahrenheit ? "°F" : "°C" }
    var targetTemp: Int? { int(P.target) }
    var indoorTemp: Int? { int(P.indoor) }
    var humidity: Int? {
        guard let h = int(P.humidity), h > 0, h < 128 else { return nil }
        return h
    }
    var tempRange: ClosedRange<Int> { fahrenheit ? 61...90 : 16...32 }

    /// Feature code 200 / 202 are cool-only units: no heat mode.
    var supportedModes: [ACMode] {
        let coolOnly = ["200", "202"].contains(featureCode)
        return [.cool, .dry, .fan, .auto] + (coolOnly ? [] : [.heat])
    }

    var alerts: [String] {
        var a: [String] = []
        if flag(P.waterFull) { a.append("Water tank full. Drain the unit.") }
        if flag(P.filter) { a.append("Filter needs cleaning.") }
        let faults = status.filter { $0.key.hasPrefix("f_e_") && $0.key != P.waterFull && $0.key != "f_e_push" && $0.value == "1" }
        if !faults.isEmpty { a.append("Fault reported: \(faults.keys.sorted().joined(separator: ", "))") }
        return a
    }
}
