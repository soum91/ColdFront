import SwiftUI

/// Exhale-style history: one continuous smooth room-temperature line with a soft fill,
/// the AC's own sensor as a faint second line, and the set temperature as a dashed step.
struct HistoryChart: View {
    let appliance: Appliance
    @ObservedObject private var history = History.shared
    @State private var range: TimeInterval = 12 * 3600

    private struct Series {
        var room: [TempPoint] = []
        var acLine: [TempPoint] = []    // only drawn when the room line comes from the Govee
        var set: [TempPoint] = []
        var roomIsGovee = false
        var start = Date()
        var end = Date()
        var lo = 18.0
        var hi = 26.0
    }

    private func build() -> Series {
        let end = Date(), start = end.addingTimeInterval(-range)
        let samples = history.samples(appliance.id, since: start)
        let step = TempSeries.step(for: range)
        let govee = samples.compactMap { s in s.govee.map { TempPoint(t: s.t, v: $0) } }
        let ac = samples.compactMap { s in s.ac.map { TempPoint(t: s.t, v: $0) } }
        var out = Series(start: start, end: end)
        out.roomIsGovee = govee.count >= 3
        // Room line: Govee where it was seen, AC sensor filling the rest, so the line never breaks.
        let room = samples.compactMap { s in (s.govee ?? s.ac).map { TempPoint(t: s.t, v: $0) } }
        out.room = TempSeries.bucket(room, from: start, to: end, step: step)
        if out.roomIsGovee { out.acLine = TempSeries.bucket(ac, from: start, to: end, step: step) }
        var last: Double?
        for s in samples {
            guard let v = s.set, v != last else { continue }
            out.set.append(TempPoint(t: s.t, v: v)); last = v
        }
        let all = out.room.map(\.v) + out.acLine.map(\.v) + out.set.map(\.v)
        (out.lo, out.hi) = TempSeries.bounds(all)
        return out
    }

    private var lineColor: Color {
        guard appliance.isOn else { return EquinoxColor.cool }
        switch appliance.mode {
        case .heat: return EquinoxColor.heat
        default: return EquinoxColor.cool
        }
    }

    var body: some View {
        let s = build()
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $range) {
                Text("6H").tag(6 * 3600.0)
                Text("12H").tag(12 * 3600.0)
                Text("24H").tag(24 * 3600.0)
                Text("7D").tag(7 * 24 * 3600.0)
            }
            .pickerStyle(.segmented)

            if s.room.count < 2 {
                Text("Building up. Readings are logged once a minute while Equinox is open, plus background checks.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 170, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                if let lo = s.room.map(\.v).min(), let hi = s.room.map(\.v).max() {
                    HStack(spacing: 14) {
                        stat("Low", lo)
                        stat("High", hi)
                        Spacer()
                    }
                }
                HStack(alignment: .top, spacing: 6) {
                    yAxis(s)
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack {
                                grid(s, geo.size)
                                if !s.acLine.isEmpty {
                                    TempCurveShape(points: s.acLine, start: s.start, end: s.end, lo: s.lo, hi: s.hi)
                                        .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                                }
                                if !s.set.isEmpty {
                                    StepShape(points: s.set, start: s.start, end: s.end, lo: s.lo, hi: s.hi)
                                        .stroke(Color.yellow.opacity(0.85), style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                                }
                                TempCurve(points: s.room, start: s.start, end: s.end, lo: s.lo, hi: s.hi, color: lineColor)
                                if let last = s.room.last {
                                    let p = TempMapper(start: s.start, end: s.end, lo: s.lo, hi: s.hi, size: geo.size).point(last)
                                    Circle().fill(lineColor).frame(width: 8, height: 8)
                                        .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1.5))
                                        .position(p)
                                }
                            }
                        }
                        .frame(height: 180)
                        xAxis(s)
                    }
                }
                HStack(spacing: 14) {
                    legend(lineColor, s.roomIsGovee ? "Room (Govee)" : "Room (AC sensor)", dashed: false)
                    if !s.acLine.isEmpty { legend(Color.white.opacity(0.4), "AC sensor", dashed: false) }
                    if !s.set.isEmpty { legend(.yellow, "Set", dashed: true) }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ label: String, _ v: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(String(format: "%.1f%@", v, appliance.unitSymbol)).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }

    private func gridValues(_ s: Series) -> [Double] {
        let span = s.hi - s.lo
        let step: Double = span > 12 ? 4 : span > 6 ? 2 : 1
        return stride(from: s.lo, through: s.hi, by: step).map { $0 }
    }

    private func grid(_ s: Series, _ size: CGSize) -> some View {
        let m = TempMapper(start: s.start, end: s.end, lo: s.lo, hi: s.hi, size: size)
        return Path { p in
            for v in gridValues(s) {
                let y = m.y(v)
                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
    }

    private func yAxis(_ s: Series) -> some View {
        GeometryReader { geo in
            let m = TempMapper(start: s.start, end: s.end, lo: s.lo, hi: s.hi, size: geo.size)
            ForEach(gridValues(s), id: \.self) { v in
                Text("\(Int(v))°").font(.system(size: 10)).foregroundStyle(.secondary)
                    .position(x: 12, y: m.y(v))
            }
        }
        .frame(width: 26, height: 180)
    }

    private func xAxis(_ s: Series) -> some View {
        let fmt: Date.FormatStyle = range > 86400 ? .dateTime.weekday(.abbreviated) : .dateTime.hour()
        return HStack {
            Text(s.start, format: fmt)
            Spacer()
            Text(s.start.addingTimeInterval(range / 2), format: fmt)
            Spacer()
            Text("Now")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private func legend(_ c: Color, _ label: String, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            Path { p in p.move(to: CGPoint(x: 0, y: 4)); p.addLine(to: CGPoint(x: 14, y: 4)) }
                .stroke(c, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [3, 2] : []))
                .frame(width: 14, height: 8)
            Text(label)
        }
    }
}
