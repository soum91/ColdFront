import Foundation
import WidgetKit

@MainActor enum ACWidgetActions {
    static func device(_ id: String) async throws -> Appliance {
        let store = Store.shared
        guard store.loggedIn else { throw EquinoxIntentError(message: "Open Equinox and sign in first.") }
        await store.refresh()
        if let error = store.error { throw EquinoxIntentError(message: error) }
        guard let a = id.isEmpty ? store.appliances.first(where: \.isAirConditioner) : store.appliance(id) else {
            throw EquinoxIntentError(message: "This air conditioner is unavailable. Open Equinox.")
        }
        guard a.online else { throw EquinoxIntentError(message: "Air conditioner is offline.") }
        return a
    }
    static func power(_ id: String, on: Bool) async throws {
        let a = try await device(id)
        let store = Store.shared
        var props = [P.power: on ? 1 : 0]
        if var smart = store.smartAuto(a) {
            if !on && smart.startupTurbo == true { props[P.turbo] = 0 }
            smart.startupTurbo = on ? false : nil
            smart.turboMode = nil
            store.smart[a.id] = smart
        }
        try await store.commit(a.id, props)
    }
    static func run(_ id: String, action: ACQuickAction) async throws {
        let a = try await device(id)
        let store = Store.shared
        var props: [String: Int] = [:]
        switch action {
        case .warmer, .cooler:
            guard a.mode.allowsTemperature || store.smartAuto(a) != nil else { throw EquinoxIntentError(message: "Choose Cool, Heat or Smart Auto before adjusting temperature.") }
            let next = min(a.tempRange.upperBound, max(a.tempRange.lowerBound, (store.displayedTarget(a) ?? (a.fahrenheit ? 72 : 22)) + (action == .warmer ? 1 : -1)))
            if var smart = store.smartAuto(a) {
                smart.setpoint = next; smart.fahrenheit = a.fahrenheit; store.smart[a.id] = smart
                // Store the target without bypassing Smart Auto's switching dwell time.
                store.publishWidgetState()
                return
            }
            props = [P.target: next]
        case .cool, .fan, .dry:
            let boosted = store.smartAuto(a)?.startupTurbo == true
            store.disableSmartAuto(a.id)
            props = [P.power: 1, P.mode: action == .cool ? 2 : action == .fan ? 0 : 3]
            if boosted { props[P.turbo] = 0 }
            if action == .cool, let target = a.targetTemp { props[P.target] = target }
        case .sleep, .eco:
            let key = action == .sleep ? P.sleep : P.eco
            guard a.has(key) else { throw EquinoxIntentError(message: "This AC does not expose that setting.") }
            props = [key: a.flag(key) ? 0 : 1]
        }
        try await store.commit(a.id, props)
    }
}
extension Store {
    func publishWidgetState() {
        let snaps = appliances.filter(\.isAirConditioner).map { a in
            ACWidgetState(id: a.id, name: a.name, on: a.isOn, room: roomTemp(a).value,
                          target: displayedTarget(a), unit: a.unitSymbol, mode: smartAuto(a) == nil ? a.mode.label : "Smart Auto", updatedAt: lastUpdated ?? .now,
                          phase: a.isOn ? (a.mode == .cool ? "cool" : a.mode == .heat ? "heat" : "other") : nil,
                          online: a.online,
                          acSensor: a.indoorTemp.map(Double.init))
        }
        if History.shared.log.isEmpty == false { History.shared.publishShared() }
        AppGroup.write(snaps, "ac-widgets.json")
        if let ac = appliances.first(where: \.isAirConditioner), let r = Govee.shared.reading(for: ac.id) {
            AppGroup.write(GoveeWidgetState(name: r.name, tempC: r.tempC, humidity: r.humidity, battery: r.battery, at: r.seen,
                                            fahrenheit: ac.fahrenheit,
                                            usedByAuto: Govee.shared.acOnly[ac.id] != true), "govee-widget.json")
        }
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
    }
}
