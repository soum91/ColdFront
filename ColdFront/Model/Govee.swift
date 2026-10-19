import Foundation
import CoreBluetooth

/// Passive listener for Govee thermo-hygrometers (H5102 and its siblings).
/// They broadcast temperature, humidity and battery in their advertisement,
/// so there's no connection or pairing, just scanning.
///
/// Advertisement (as iOS delivers it, company ID first, little-endian):
///   01 00 | xx xx | T2 T1 T0 | B
///   T = 24-bit packed value: bit 23 = negative, temp = (v & 0x7FFFFF) / 1000 / 10 °C, humidity = (v % 1000) / 10 %
///   B = battery % (top bit = sensor error flag)
final class Govee: NSObject, ObservableObject, CBCentralManagerDelegate {
    static let shared = Govee()

    struct Reading: Identifiable, Equatable {
        let id: String          // CBPeripheral identifier
        var name: String
        var tempC: Double
        var humidity: Double
        var battery: Int
        var rssi: Int
        var seen: Date

        var isFresh: Bool { Date().timeIntervalSince(seen) < 5 * 60 }
    }

    @Published private(set) var readings: [String: Reading] = [:]
    @Published private(set) var bluetoothOff = false
    /// applianceId -> sensor id
    @Published var links: [String: String] = UserDefaults.standard.dictionary(forKey: "govee.links") as? [String: String] ?? [:] {
        didSet { UserDefaults.standard.set(links, forKey: "govee.links") }
    }
    /// applianceId -> true if Auto should ignore the Govee and use the AC's own sensor
    @Published var acOnly: [String: Bool] = UserDefaults.standard.dictionary(forKey: "govee.acOnly") as? [String: Bool] ?? [:] {
        didSet { UserDefaults.standard.set(acOnly, forKey: "govee.acOnly") }
    }

    private var central: CBCentralManager?
    private var wantScan = false

    func start() {
        wantScan = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)  // main queue
        } else if central?.state == .poweredOn {
            scan()
        }
    }

    func stop() {
        wantScan = false
        central?.stopScan()
    }

    func reading(for applianceId: String) -> Reading? {
        guard let id = links[applianceId] else { return nil }
        return readings[id]
    }

    private func scan() {
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        bluetoothOff = c.state != .poweredOn
        if c.state == .poweredOn, wantScan { scan() }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = (ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        let id = p.identifier.uuidString
        let upper = name.uppercased()
        let goveeName = upper.hasPrefix("GV") || upper.contains("GOVEE") || upper.hasPrefix("IHOME")
            || ["H5072", "H5074", "H5075", "H5100", "H5101", "H5102", "H5103", "H5104", "H5105",
                "H5108", "H5110", "H5174", "H5177", "H5179"].contains { upper.contains($0) }

        guard let mfr = ad[CBAdvertisementDataManufacturerDataKey] as? Data, mfr.count >= 2 else {
            if goveeName { noteRaw(id, name, "(no manufacturer data)", rssi) }
            return
        }
        let b = [UInt8](mfr)
        let company = Int(b[0]) | (Int(b[1]) << 8)
        let payload = Array(b.dropFirst(2))
        if company == 0x004C { return }  // Apple iBeacon frame, the same sensors alternate with it

        if goveeName || company == 0xEC88 || company == 0x0001 {
            noteRaw(id, name, b.map { String(format: "%02X", $0) }.joined(separator: " "), rssi)
        }

        // Same rules as the Home Assistant govee-ble parser:
        //  H5072/H5075 (or company 0xEC88): 6 bytes, value in payload[1...4]
        //  H5100-H5110/H5174/H5177/H5179 (any company ID): 6 or 8 bytes, value in payload[2...5]
        var bytes: ArraySlice<UInt8>?
        if payload.count == 6, upper.contains("H5072") || upper.contains("H5075") || company == 0xEC88 {
            bytes = payload[1...4]
        } else if payload.count == 6 || payload.count == 8, goveeName || company == 0x0001 {
            bytes = payload[2...5]
        }
        guard let v4 = bytes.map({ Array($0) }), v4.count == 4 else { return }

        let raw = (Int(v4[0]) << 16) | (Int(v4[1]) << 8) | Int(v4[2])
        let negative = raw & 0x800000 != 0
        let v = raw & 0x7FFFFF
        var temp = Double(v / 1000) / 10.0
        if negative { temp = -temp }
        let hum = Double(v % 1000) / 10.0
        let err = v4[3] & 0x80 != 0
        guard !err, temp > -40, temp < 70, hum >= 0, hum <= 100 else { return }

        if let old = readings[id], old.tempC == temp, old.humidity == hum,
           Date().timeIntervalSince(old.seen) < 15 { return }   // throttle UI churn
        let display = name.isEmpty ? "Govee sensor" : name.replacingOccurrences(of: "_", with: " ")
        readings[id] = Reading(id: id, name: display, tempC: temp, humidity: hum,
                               battery: Int(v4[3] & 0x7F), rssi: rssi.intValue, seen: Date())
    }

    // MARK: Debug: raw frames from anything Govee-looking, so unknown models can be mapped.

    struct Raw: Identifiable { let id: String; var name: String; var hex: String; var rssi: Int }
    @Published private(set) var raw: [String: Raw] = [:]

    private func noteRaw(_ id: String, _ name: String, _ hex: String, _ rssi: NSNumber) {
        if raw[id]?.hex == hex { return }
        raw[id] = Raw(id: id, name: name.isEmpty ? "(no name)" : name, hex: hex, rssi: rssi.intValue)
    }
}
