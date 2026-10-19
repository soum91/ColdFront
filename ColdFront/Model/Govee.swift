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
        guard let mfr = ad[CBAdvertisementDataManufacturerDataKey] as? Data else { return }
        let b = [UInt8](mfr)
        let looksGovee = name.contains("H510") || name.contains("H5174") || name.contains("H5177") || name.hasPrefix("GVH")
        // Company 0x0001, 6 data bytes (8 with the ID). Name check guards against random 0x0001 advertisers.
        guard b.count == 8, b[0] == 0x01, b[1] == 0x00, looksGovee || readings[p.identifier.uuidString] != nil else { return }

        let raw = (Int(b[4]) << 16) | (Int(b[5]) << 8) | Int(b[6])
        let negative = raw & 0x800000 != 0
        let v = raw & 0x7FFFFF
        var temp = Double(v / 1000) / 10.0
        if negative { temp = -temp }
        let hum = Double(v % 1000) / 10.0
        let err = b[7] & 0x80 != 0
        guard !err, temp > -40, temp < 70, hum >= 0, hum <= 100 else { return }

        let id = p.identifier.uuidString
        if let old = readings[id], old.tempC == temp, old.humidity == hum,
           Date().timeIntervalSince(old.seen) < 15 { return }   // throttle UI churn
        let display = name.isEmpty ? "Govee sensor" : name.replacingOccurrences(of: "_", with: " ")
        readings[id] = Reading(id: id, name: display, tempC: temp, humidity: hum,
                               battery: Int(b[7] & 0x7F), rssi: rssi.intValue, seen: Date())
    }
}
