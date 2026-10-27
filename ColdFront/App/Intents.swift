import AppIntents
import Foundation

// Shortcuts actions. Scheduling and triggers (time of day, arriving home, leaving, alarm, focus)
// live in the Shortcuts app's Automation tab, which runs these reliably without the app open.

struct EquinoxIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
}

struct SceneEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Scene"
    static var defaultQuery = SceneQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(_ s: ACScene) {
        id = s.id
        name = s.name
    }
}

struct SceneQuery: EntityQuery {
    func entities(for identifiers: [SceneEntity.ID]) async throws -> [SceneEntity] {
        ScenesStore.load().filter { identifiers.contains($0.id) }.map(SceneEntity.init)
    }

    func suggestedEntities() async throws -> [SceneEntity] {
        ScenesStore.load().map(SceneEntity.init)
    }
}

@MainActor
private func signedInStore() throws -> Store {
    let store = Store.shared
    guard store.loggedIn else { throw EquinoxIntentError(message: "Open Equinox and sign in first.") }
    return store
}

struct RunSceneIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Scene"
    static var description = IntentDescription("Applies one of your Equinox scenes to the air conditioner.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Scene")
    var scene: SceneEntity

    static var parameterSummary: some ParameterSummary { Summary("Run \(\.$scene)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try signedInStore()
        guard let s = ScenesStore.load().first(where: { $0.id == scene.id }) else {
            throw EquinoxIntentError(message: "That scene no longer exists.")
        }
        await store.refresh()
        try await store.runScene(s)
        return .result(dialog: IntentDialog(stringLiteral: "\(s.name) applied."))
    }
}

struct TurnOffACIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn Off AC"
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try signedInStore()
        await store.refresh()
        try await store.runScene(ACScene(name: "Off", icon: "power", power: false))
        return .result(dialog: "AC off.")
    }
}

struct TurnOnACIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn On AC"
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try signedInStore()
        await store.refresh()
        try await store.runScene(ACScene(name: "On", icon: "power"))
        return .result(dialog: "AC on.")
    }
}

struct SetTemperatureIntent: AppIntent {
    static var title: LocalizedStringResource = "Set AC Temperature"
    static var description = IntentDescription("Sets the target temperature (in the unit the AC is using). Turns the AC on if it's off.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Temperature", inclusiveRange: (16, 90))
    var temperature: Int

    static var parameterSummary: some ParameterSummary { Summary("Set AC to \(\.$temperature)°") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try signedInStore()
        await store.refresh()
        let f = store.appliances.first(where: \.isAirConditioner)?.fahrenheit ?? false
        try await store.runScene(ACScene(name: "Temp", icon: "thermometer", temp: temperature, tempFahrenheit: f))
        return .result(dialog: IntentDialog(stringLiteral: "Set to \(temperature)\(f ? "°F" : "°C")."))
    }
}

struct GetRoomTemperatureIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Room Temperature"
    static var description = IntentDescription("The room temperature Equinox is using (Govee if fresh, otherwise the AC's sensor). Use it in an If block to build conditional automations.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let store = try signedInStore()
        await store.refresh()
        guard let a = store.appliances.first(where: \.isAirConditioner),
              let v = store.roomTemp(a).value else {
            throw EquinoxIntentError(message: "No temperature reading right now.")
        }
        return .result(value: v, dialog: IntentDialog(stringLiteral: String(format: "%.1f%@", v, a.unitSymbol)))
    }
}

/// App-only one-tap action for Apple's Shortcut control in Control Center.
struct ToggleACShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle AC Power"
    static var description = IntentDescription("Switches the air conditioner on or off.")

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = try signedInStore()
        await store.refresh()
        let air = store.appliances.filter { $0.isAirConditioner && $0.online }
        guard !air.isEmpty else { throw EquinoxIntentError(message: "No online air conditioner.") }
        let anyOn = air.contains(where: \.isOn)
        try await store.runScene(ACScene(name: anyOn ? "Off" : "On", icon: "power", power: !anyOn))
        return .result()
    }
}

struct EquinoxShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RunSceneIntent(),
                    phrases: ["Run a scene in \(.applicationName)", "Run an \(.applicationName) scene"],
                    shortTitle: "Run Scene", systemImageName: "sparkles")
        AppShortcut(intent: ToggleACShortcutIntent(),
                    phrases: ["Toggle the AC in \(.applicationName)", "Switch the AC with \(.applicationName)"],
                    shortTitle: "AC Switch", systemImageName: "air.conditioner.horizontal")
        AppShortcut(intent: TurnOffACIntent(),
                    phrases: ["Turn off the AC with \(.applicationName)"],
                    shortTitle: "Turn Off AC", systemImageName: "power")
        AppShortcut(intent: TurnOnACIntent(),
                    phrases: ["Turn on the AC with \(.applicationName)"],
                    shortTitle: "Turn On AC", systemImageName: "power.circle")
        AppShortcut(intent: GetRoomTemperatureIntent(),
                    phrases: ["Room temperature in \(.applicationName)"],
                    shortTitle: "Room Temperature", systemImageName: "thermometer.medium")
    }
}
