import Foundation

/// The room reading from the Govee, for the Govee widget. The app writes it; the widget also asks the
/// Keystone Bridge directly, because iOS gives neither the app nor the widget Bluetooth in the background
/// and the bridge listens all day.
struct GoveeWidgetState: Codable, Equatable {
    var name: String
    var tempC: Double
    var humidity: Double
    var battery: Int
    var at: Date
    var fahrenheit: Bool
    var usedByAuto: Bool = false      // Smart reads this sensor (not the AC's own)

    static func load() -> GoveeWidgetState? { AppGroup.read(GoveeWidgetState.self, "govee-widget.json") }
}

struct BridgeHostFile: Codable { var host: String; var port: Int }

enum GoveeFeed {
    static func parse(_ g: [String: Any]) -> (name: String, t: Double, h: Double, b: Int, at: Date)? {
        guard let t = (g["temp"] as? NSNumber)?.doubleValue, let h = (g["humidity"] as? NSNumber)?.doubleValue else { return nil }
        let ago = (g["heardAgo"] as? NSNumber)?.doubleValue ?? 0
        return ((g["name"] as? String) ?? "Govee", t, h, (g["battery"] as? NSNumber)?.intValue ?? -1,
                Date().addingTimeInterval(-max(0, ago)))
    }

    /// Straight from the bridge (home Wi-Fi). Nil if it's not reachable or hasn't heard the sensor.
    static func fetchBridge(timeout: TimeInterval = 5) async -> GoveeWidgetState? {
        guard let h = AppGroup.read(BridgeHostFile.self, "bridge-host.json"),
              let u = URL(string: "http://\(h.host):\(h.port)/api/info?lite=1") else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let g = obj["govee"] as? [String: Any], let p = parse(g) else { return nil }
        let old = GoveeWidgetState.load()
        return GoveeWidgetState(name: p.name, tempC: p.t, humidity: p.h, battery: p.b, at: p.at,
                                fahrenheit: old?.fahrenheit ?? false, usedByAuto: old?.usedByAuto ?? false)
    }
}
