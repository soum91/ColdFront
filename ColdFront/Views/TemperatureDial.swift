import SwiftUI

/// 270° arc dial. Drag around the ring or tap -/+ to change the setpoint; sends on release.
struct TemperatureDial: View {
    @EnvironmentObject var store: Store
    let appliance: Appliance
    let accent: Color

    @State private var dragValue: Int?
    private let sweep: Double = 270
    private let size: CGFloat = 270

    private var range: ClosedRange<Int> { appliance.tempRange }
    private var smart: SmartAuto? { store.smartAuto(appliance) }
    private var shown: Int { dragValue ?? store.displayedTarget(appliance) ?? range.lowerBound }
    private var enabled: Bool { appliance.isOn && (smart != nil || appliance.mode.allowsTemperature) }
    private var modeLabel: String {
        guard appliance.isOn else { return "OFF" }
        guard smart != nil else { return appliance.mode.label.uppercased() }
        switch appliance.mode {
        case .cool: return "AUTO · COOLING"
        case .heat: return "AUTO · HEATING"
        default: return "AUTO · IDLE"
        }
    }
    private var fraction: Double {
        Double(shown - range.lowerBound) / Double(range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                ring(trim: 1, color: Color.white.opacity(0.08))
                ring(trim: enabled ? fraction : 0, color: accent)
                    .shadow(color: accent.opacity(0.6), radius: 12)
                    .animation(.spring(response: 0.35), value: fraction)

                if enabled { knob }

                VStack(spacing: 2) {
                    Text(modeLabel)
                        .font(.caption.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 2) {
                        Text(enabled ? "\(shown)" : "--")
                            .font(.system(size: 76, weight: .thin, design: .rounded))
                            .contentTransition(.numericText(value: Double(shown)))
                        Text(appliance.unitSymbol)
                            .font(.system(size: 22, weight: .light, design: .rounded))
                            .padding(.top, 14)
                    }
                    if let i = appliance.indoorTemp {
                        Text("Room \(i)\(appliance.unitSymbol)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(drag, including: enabled ? .all : .none)

            HStack(spacing: 40) {
                stepButton("minus", -1)
                stepButton("plus", 1)
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.35)
        }
        .sensoryFeedback(.selection, trigger: dragValue)
    }

    private func ring(trim: Double, color: Color) -> some View {
        Circle()
            .trim(from: 0, to: sweep / 360 * trim)
            .stroke(color, style: StrokeStyle(lineWidth: 18, lineCap: .round))
            .rotationEffect(.degrees(90 + (360 - sweep) / 2))
            .padding(12)
    }

    private var knob: some View {
        let angle = Angle.degrees(90 + (360 - sweep) / 2 + sweep * fraction)
        let r = size / 2 - 12
        return Circle()
            .fill(.white)
            .frame(width: 26, height: 26)
            .shadow(radius: 4)
            .offset(x: cos(angle.radians) * r, y: sin(angle.radians) * r)
            .animation(.spring(response: 0.35), value: fraction)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let c = CGPoint(x: size / 2, y: size / 2)
                var deg = atan2(g.location.y - c.y, g.location.x - c.x) * 180 / .pi
                // Map so the arc start (bottom-left) is 0.
                deg -= 90 + (360 - sweep) / 2
                while deg < 0 { deg += 360 }
                if deg > sweep {
                    // dead zone at the bottom: snap to whichever end is closer
                    deg = deg > sweep + (360 - sweep) / 2 ? 0 : sweep
                }
                let span = Double(range.upperBound - range.lowerBound)
                dragValue = range.lowerBound + Int((deg / sweep * span).rounded())
            }
            .onEnded { _ in
                if let v = dragValue, v != store.displayedTarget(appliance) {
                    store.setTemp(appliance, v)
                }
                // let the optimistic store value take over
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { dragValue = nil }
            }
    }

    private func stepButton(_ icon: String, _ delta: Int) -> some View {
        Button {
            store.setTemp(appliance, shown + delta)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 64, height: 64)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.increase, trigger: shown)
    }
}
