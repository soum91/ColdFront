import SwiftUI

enum Theme {
    static let bgTop = Color(red: 0.05, green: 0.07, blue: 0.10)
    static let bgBottom = Color(red: 0.02, green: 0.03, blue: 0.05)
    static let card = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.08)

    static func accent(_ a: Appliance) -> Color {
        guard a.isOn, a.online else { return Color(white: 0.45) }
        switch a.mode {
        case .cool: return Color(red: 0.30, green: 0.70, blue: 1.00)
        case .heat: return Color(red: 1.00, green: 0.55, blue: 0.25)
        case .dry: return Color(red: 0.25, green: 0.85, blue: 0.75)
        case .fan: return Color(red: 0.70, green: 0.75, blue: 0.85)
        case .auto: return Color(red: 0.60, green: 0.55, blue: 1.00)
        }
    }

    static func background(_ accent: Color) -> some View {
        ZStack {
            LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [accent.opacity(0.28), .clear], center: .top, startRadius: 10, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}
