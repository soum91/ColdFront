import Foundation

/// A saved bundle of settings applied in one command (one beep). Any nil field means "leave as is".
/// `mode == ACMode.auto` means Equinox's Smart Auto, not the unit's native auto.
struct ACScene: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var icon: String
    var power: Bool = true
    var mode: Int?
    var temp: Int?
    var tempFahrenheit: Bool = false
    var fan: Int?
    var sleep: Bool?
    var eco: Bool?
    var dimmer: Bool?
    var onArrive: Bool?
    var onLeave: Bool?

    var acMode: ACMode? { mode.flatMap(ACMode.init(rawValue:)) }

    var summary: String {
        guard power else { return "Turn off" }
        var parts: [String] = []
        if let m = acMode { parts.append(m == .auto ? "Smart" : m.label) }
        if let t = temp { parts.append("\(t)\(tempFahrenheit ? "°F" : "°C")") }
        if let f = fan, let fs = FanSpeed(rawValue: f) { parts.append("fan \(fs.label.lowercased())") }
        if sleep == true { parts.append("sleep") }
        if eco == true { parts.append("eco") }
        return parts.isEmpty ? "Turn on" : parts.joined(separator: " · ")
    }

    static let defaults: [ACScene] = [
        ACScene(name: "Comfort", icon: "sofa", mode: ACMode.auto.rawValue, temp: 21, fan: FanSpeed.auto.rawValue),
        ACScene(name: "Sleep", icon: "moon.zzz", mode: ACMode.auto.rawValue, temp: 20, fan: FanSpeed.quiet.rawValue, sleep: true),
        ACScene(name: "Off", icon: "power", power: false)
    ]
}

enum ScenesStore {
    private static let key = "scenes.v1"

    static func load() -> [ACScene] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([ACScene].self, from: data) else { return ACScene.defaults }
        return list
    }

    static func save(_ list: [ACScene]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }
}
