import SwiftUI
import Charts

struct HistoryChart: View {
    let appliance: Appliance
    @ObservedObject private var history = History.shared
    @State private var range: TimeInterval = 6 * 3600

    private struct Point: Identifiable {
        let id = UUID()
        let t: Date
        let v: Double
        let series: String     // legend / colour
        let segment: String    // breaks the line across gaps when the app wasn't running
    }

    var body: some View {
        let samples = history.samples(appliance.id, since: Date().addingTimeInterval(-range))
        let points = makePoints(samples)
        let timeFormat: Date.FormatStyle = range > 86400 ? .dateTime.weekday(.abbreviated) : .dateTime.hour()
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $range) {
                Text("6H").tag(6 * 3600.0)
                Text("24H").tag(24 * 3600.0)
                Text("7D").tag(7 * 24 * 3600.0)
            }
            .pickerStyle(.segmented)

            if points.count < 2 {
                Text("Building up. History is logged once a minute while Equinox is open, plus the odd background check.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                Chart {
                    ForEach(modeBands(samples)) { band in
                        RectangleMark(xStart: .value("From", band.from), xEnd: .value("To", band.to))
                            .foregroundStyle(band.color.opacity(0.12))
                    }
                    ForEach(points) { p in
                        LineMark(x: .value("Time", p.t), y: .value("Temp", p.v), series: .value("Line", p.segment))
                            .foregroundStyle(by: .value("Series", p.series))
                            .interpolationMethod(p.series == "Set" ? .stepEnd : .monotone)
                            .lineStyle(StrokeStyle(lineWidth: p.series == "Set" ? 1.5 : 2.2,
                                                   dash: p.series == "Set" ? [4, 3] : []))
                    }
                }
                .chartForegroundStyleScale([
                    "AC sensor": Color(white: 0.75),
                    "Govee": Color(red: 0.3, green: 0.85, blue: 0.75),
                    "Set": Color.yellow
                ])
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))°") } }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel(format: timeFormat)
                    }
                }
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 190)

                HStack(spacing: 14) {
                    legendSwatch(Color(red: 0.30, green: 0.70, blue: 1.00), "Cooling")
                    legendSwatch(Color(red: 1.00, green: 0.55, blue: 0.25), "Heating")
                    legendSwatch(Color(white: 0.6), "Fan/Dry")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func legendSwatch(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(c.opacity(0.35)).frame(width: 12, height: 8)
            Text(label)
        }
    }

    private func makePoints(_ samples: [History.Sample]) -> [Point] {
        var out: [Point] = []
        var seg = 0
        var prev: Date?
        for s in samples {
            if let p = prev, s.t.timeIntervalSince(p) > 10 * 60 { seg += 1 }
            prev = s.t
            if let v = s.ac { out.append(Point(t: s.t, v: v, series: "AC sensor", segment: "ac\(seg)")) }
            if let v = s.govee { out.append(Point(t: s.t, v: v, series: "Govee", segment: "gv\(seg)")) }
            if let v = s.set { out.append(Point(t: s.t, v: v, series: "Set", segment: "set\(seg)")) }
        }
        return out
    }

    private struct Band: Identifiable {
        let id = UUID()
        let from: Date
        let to: Date
        let color: Color
    }

    /// Shaded background showing what the unit was doing.
    private func modeBands(_ samples: [History.Sample]) -> [Band] {
        var bands: [Band] = []
        var i = 0
        while i < samples.count {
            let m = samples[i].mode
            var j = i
            while j + 1 < samples.count, samples[j + 1].mode == m,
                  samples[j + 1].t.timeIntervalSince(samples[j].t) < 10 * 60 { j += 1 }
            if let m {
                let end = j + 1 < samples.count && samples[j + 1].t.timeIntervalSince(samples[j].t) < 10 * 60
                    ? samples[j + 1].t : samples[j].t.addingTimeInterval(60)
                let color: Color = m == ACMode.cool.rawValue ? Color(red: 0.30, green: 0.70, blue: 1.00)
                    : m == ACMode.heat.rawValue ? Color(red: 1.00, green: 0.55, blue: 0.25)
                    : Color(white: 0.6)
                bands.append(Band(from: samples[i].t, to: end, color: color))
            }
            i = j + 1
        }
        return bands
    }
}
