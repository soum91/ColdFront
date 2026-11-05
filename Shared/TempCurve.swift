import SwiftUI

/// One temperature reading on a chart. Shared by the in-app history chart and the widgets.
struct TempPoint: Codable, Hashable {
    var t: Date
    var v: Double
}

enum TempSeries {
    /// Averages readings into time buckets and lightly smooths them, giving one continuous line
    /// (Exhale style): gaps where the app wasn't running are bridged instead of breaking the line,
    /// and the AC's whole-degree readings stop looking like a staircase.
    static func bucket(_ pts: [TempPoint], from start: Date, to end: Date, step: TimeInterval) -> [TempPoint] {
        let relevant = pts.filter { $0.t >= start && $0.t <= end }
        guard !relevant.isEmpty else { return [] }
        var buckets: [Int: (sum: Double, n: Int, last: Date)] = [:]
        for p in relevant {
            let i = Int(p.t.timeIntervalSince(start) / step)
            let b = buckets[i] ?? (0, 0, p.t)
            buckets[i] = (b.sum + p.v, b.n + 1, max(b.last, p.t))
        }
        var out: [TempPoint] = buckets.keys.sorted().map { i in
            let b = buckets[i]!
            let center = start.addingTimeInterval((Double(i) + 0.5) * step)
            return TempPoint(t: min(center, b.last), v: b.sum / Double(b.n))
        }
        if out.count >= 5 {
            let raw = out
            for i in 1..<(raw.count - 1) {
                out[i].v = (raw[i - 1].v + 2 * raw[i].v + raw[i + 1].v) / 4
            }
        }
        return out
    }

    /// Bucket size that keeps any range to roughly 50-80 points.
    static func step(for range: TimeInterval) -> TimeInterval {
        switch range {
        case ...(6.5 * 3600): return 5 * 60
        case ...(13 * 3600): return 10 * 60
        case ...(25 * 3600): return 20 * 60
        default: return 2 * 3600
        }
    }

    /// Whole-degree bounds with a little headroom, at least 4° tall so a flat room doesn't look like a cliff.
    static func bounds(_ values: [Double]) -> (lo: Double, hi: Double) {
        guard let mn = values.min(), let mx = values.max() else { return (18, 26) }
        var lo = floor(mn - 0.6), hi = ceil(mx + 0.6)
        if hi - lo < 4 {
            let mid = (hi + lo) / 2
            lo = floor(mid - 2); hi = lo + 4
        }
        return (lo, hi)
    }
}

struct TempMapper {
    let start: Date
    let end: Date
    let lo: Double
    let hi: Double
    let size: CGSize

    func x(_ d: Date) -> CGFloat {
        let span = max(end.timeIntervalSince(start), 1)
        return CGFloat(d.timeIntervalSince(start) / span) * size.width
    }

    func y(_ v: Double) -> CGFloat {
        let f = (min(max(v, lo), hi) - lo) / max(hi - lo, 0.1)
        return size.height - CGFloat(f) * size.height
    }

    func point(_ p: TempPoint) -> CGPoint { CGPoint(x: x(p.t), y: y(p.v)) }
}

/// Smooth curve through the points (monotone cubic: no overshoot, no fake bumps).
struct TempCurveShape: Shape {
    var points: [TempPoint]
    var start: Date
    var end: Date
    var lo: Double
    var hi: Double
    var filled: Bool = false

    func path(in rect: CGRect) -> Path {
        let m = TempMapper(start: start, end: end, lo: lo, hi: hi, size: rect.size)
        let pts = points.map(m.point)
        var path = Path()
        guard let first = pts.first else { return path }
        if pts.count == 1 {
            path.move(to: CGPoint(x: first.x - 2, y: first.y))
            path.addLine(to: CGPoint(x: first.x + 2, y: first.y))
            return path
        }
        if filled {
            path.move(to: CGPoint(x: first.x, y: rect.height))
            path.addLine(to: first)
        } else {
            path.move(to: first)
        }
        Self.addMonotone(pts, to: &path)
        if filled {
            path.addLine(to: CGPoint(x: pts.last!.x, y: rect.height))
            path.closeSubpath()
        }
        return path
    }

    static func addMonotone(_ p: [CGPoint], to path: inout Path) {
        let n = p.count
        guard n > 1 else { return }
        var dx = [CGFloat](repeating: 0, count: n - 1)
        var slope = [CGFloat](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            dx[i] = max(p[i + 1].x - p[i].x, 0.0001)
            slope[i] = (p[i + 1].y - p[i].y) / dx[i]
        }
        var tangent = [CGFloat](repeating: 0, count: n)
        tangent[0] = slope[0]
        tangent[n - 1] = slope[n - 2]
        if n > 2 {
            for i in 1..<(n - 1) {
                let m0 = slope[i - 1], m1 = slope[i]
                if m0 * m1 <= 0 {
                    tangent[i] = 0
                } else {
                    let w1 = 2 * dx[i] + dx[i - 1]
                    let w2 = dx[i] + 2 * dx[i - 1]
                    tangent[i] = (w1 + w2) / (w1 / m0 + w2 / m1)
                }
            }
        }
        for i in 0..<(n - 1) {
            let h = dx[i] / 3
            path.addCurve(to: p[i + 1],
                          control1: CGPoint(x: p[i].x + h, y: p[i].y + tangent[i] * h),
                          control2: CGPoint(x: p[i + 1].x - h, y: p[i + 1].y - tangent[i + 1] * h))
        }
    }
}

/// Setpoint as a dashed step line (it changes in jumps, so it shouldn't be smoothed).
struct StepShape: Shape {
    var points: [TempPoint]
    var start: Date
    var end: Date
    var lo: Double
    var hi: Double

    func path(in rect: CGRect) -> Path {
        let m = TempMapper(start: start, end: end, lo: lo, hi: hi, size: rect.size)
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: m.point(first))
        var prevY = m.y(first.v)
        for p in points.dropFirst() {
            let x = m.x(p.t), y = m.y(p.v)
            path.addLine(to: CGPoint(x: x, y: prevY))
            path.addLine(to: CGPoint(x: x, y: y))
            prevY = y
        }
        path.addLine(to: CGPoint(x: m.x(min(end, Date())), y: prevY))
        return path
    }
}

/// The Exhale look for temperature: soft gradient fill under a smooth line, tinted by what the AC is doing.
struct TempCurve: View {
    var points: [TempPoint]
    var start: Date
    var end: Date
    var lo: Double
    var hi: Double
    var color: Color
    var lineWidth: CGFloat = 2.5
    var fillOpacity: Double = 0.35

    var body: some View {
        ZStack {
            TempCurveShape(points: points, start: start, end: end, lo: lo, hi: hi, filled: true)
                .fill(LinearGradient(colors: [color.opacity(fillOpacity), color.opacity(0)], startPoint: .top, endPoint: .bottom))
            TempCurveShape(points: points, start: start, end: end, lo: lo, hi: hi)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

enum EquinoxColor {
    static let cool = Color(red: 0.30, green: 0.70, blue: 1.00)
    static let heat = Color(red: 1.00, green: 0.55, blue: 0.25)
    static let idle = Color(red: 0.62, green: 0.70, blue: 0.82)
    static let off = Color(white: 0.55)

    /// phase: "cool", "heat", "other" or nil (off)
    static func of(_ phase: String?) -> Color {
        switch phase {
        case "cool": return cool
        case "heat": return heat
        case nil: return off
        default: return idle
        }
    }
}

/// Last 12 h of room and setpoint per AC, written by the app for the widgets.
struct ACHistoryWire: Codable {
    var room: [TempPoint]
    var set: [TempPoint]

    static let file = "ac-history.json"
    static func load() -> [String: ACHistoryWire] { AppGroup.read([String: ACHistoryWire].self, file) ?? [:] }
}
