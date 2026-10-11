import Foundation

struct AnalyticsChartReading: Identifiable {
    let point: AnalyticsTrendPoint
    let segment: String
    let value: Double
    var id: String { point.id }
    static func readings(_ points: [AnalyticsTrendPoint], metric: AnalyticsMetric) -> [Self] {
        var result: [Self] = []
        for (series, points) in Dictionary(grouping: points, by: \.seriesID).sorted(by: { $0.key < $1.key }) {
            var segment = 0
            for point in points.sorted(by: { $0.date < $1.date }) {
                guard let value = metric.value(point.values) else { segment += 1; continue }
                result.append(Self(point: point, segment: "\(series)|\(segment)", value: value))
            }
        }
        return result
    }
}
