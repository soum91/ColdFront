import Foundation
import AppIntents
import WidgetKit

struct ACWidgetState: Codable, Identifiable {
    var id: String
    var name: String
    var on: Bool
    var room: Double?
    var target: Int?
    var unit: String
    var mode: String
    var updatedAt: Date
    static func load() -> [ACWidgetState] { AppGroup.read([ACWidgetState].self, "ac-widgets.json") ?? [] }
}
struct ACEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Air conditioner"
    static var defaultQuery = ACQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
}
struct ACQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ACEntity] { try await suggestedEntities().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [ACEntity] { ACWidgetState.load().map { .init(id: $0.id, name: $0.name) } }
}
struct ACWidgetConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Air conditioner"
    @Parameter(title: "Air conditioner") var device: ACEntity?
}
@available(iOS 18.0, *) struct ACControlConfig: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "AC action"
    @Parameter(title: "Air conditioner") var device: ACEntity?
    @Parameter(title: "Action", default: .cool) var action: ACQuickAction
}
enum ACQuickAction: String, AppEnum {
    case warmer, cooler, cool, fan, dry, sleep, eco
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "AC action"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .warmer: "Temperature up", .cooler: "Temperature down", .cool: "Cool", .fan: "Fan", .dry: "Dry", .sleep: "Toggle Sleep", .eco: "Toggle Eco"]
    var symbol: String {
        switch self { case .warmer: return "plus"; case .cooler: return "minus"; case .cool: return "snowflake"; case .fan: return "fan"; case .dry: return "drop"; case .sleep: return "moon.fill"; case .eco: return "leaf.fill" }
    }
}
struct ACActionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Control Equinox"
    @Parameter(title: "Device ID") var deviceID: String
    @Parameter(title: "Action") var action: ACQuickAction
    init() { deviceID = ""; action = .cool }
    init(_ id: String, _ action: ACQuickAction) { deviceID = id; self.action = action }
    @MainActor func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        try await ACWidgetActions.run(deviceID, action: action)
        #endif
        return .result()
    }
}
@available(iOS 18.0, *) struct ACPowerIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "AC power"
    @Parameter(title: "Device ID") var deviceID: String
    @Parameter(title: "On") var value: Bool
    init() { deviceID = "" }
    init(_ id: String) { deviceID = id }
    @MainActor func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        try await ACWidgetActions.power(deviceID, on: value)
        #endif
        return .result()
    }
}
struct ACToggleIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle AC"
    @Parameter(title: "Device ID") var deviceID: String
    init() { deviceID = "" }
    init(_ id: String) { deviceID = id }
    @MainActor func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let a = try await ACWidgetActions.device(deviceID)
        try await ACWidgetActions.power(a.id, on: !a.isOn)
        #endif
        return .result()
    }
}
