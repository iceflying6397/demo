import SwiftUI
import Charts

struct AnalyticsTrendView: View {
    let report: AnalyticsReport
    @Binding var metric: AnalyticsMetric
    private var readings: [AnalyticsChartReading] { AnalyticsChartReading.readings(report.points, metric: metric) }
    private var plans: [Int] { Array(Set(report.performances.map(\.planNumber))).sorted() }
    var body: some View {
        DemoCard {
            Text("\(metric.rawValue)趋势 · \(metric.unit)").font(DemoTheme.Typography.heading)
            Picker("趋势指标", selection: $metric) {
                ForEach(AnalyticsMetric.chartMetrics) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("analytics.trend.metric")
            Text("业务日粒度 · 仅展示有观测的日期，按批次独立连线；期间合计使用去重摘要。")
                .font(DemoTheme.Typography.caption).foregroundStyle(DemoTheme.ColorToken.secondaryText)
            if readings.isEmpty {
                DemoEmptyState(title: report.points.isEmpty ? "暂无趋势点" : "该指标统计中或缺失", message: "未知值不会画成0；可查看日期明细。")
            } else {
                Chart(readings) { reading in
                    LineMark(x: .value("业务日期", reading.point.date), y: .value(metric.unit, reading.value),
                             series: .value("批次和连续段", reading.segment))
                        .foregroundStyle(DemoTheme.ColorToken.primaryText)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: reading.point.planNumber == 2 ? [6, 4] : []))
                    PointMark(x: .value("业务日期", reading.point.date), y: .value(metric.unit, reading.value))
                        .foregroundStyle(DemoTheme.ColorToken.primaryText)
                }
                .chartXScale(domain: report.query.period.range.start...report.query.period.range.displayEnd)
                .chartYScale(domain: 0...max(1, (readings.map(\.value).max() ?? 1) * 1.1))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month().day()) } }
                .chartYAxisLabel(metric.unit)
                .chartLegend(.hidden)
                .frame(height: 220)
                .accessibilityLabel("\(metric.rawValue)趋势，单位\(metric.unit)，下方日期明细提供全部读数。")
            }
            ForEach(plans, id: \.self) { number in
                Label("\(DemoFormat.numbered("方案", number)) · \(number == 2 ? "虚线" : "实线")",
                      systemImage: number == 2 ? "line.diagonal" : "minus")
                    .font(DemoTheme.Typography.caption)
            }
            NavigationLink("查看日期读数与缺失状态") { AnalyticsDateReadingsView(report: report, metric: metric) }
                .buttonStyle(DemoSecondaryButtonStyle())
                .accessibilityIdentifier("analytics.trend.readings")
        }
    }
}

struct AnalyticsDateReadingsView: View {
    let report: AnalyticsReport
    @State var metric: AnalyticsMetric
    var body: some View {
        List {
            Section {
                Text(report.query.period.range.label)
                Picker("指标", selection: $metric) {
                    ForEach(AnalyticsMetric.chartMetrics) { Text($0.rawValue).tag($0) }
                }
                Text("业务日；每天转化率从当天分子分母计算。跨日客户可能重复，期间人数不由本表累加。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if report.points.isEmpty { Section { Text("暂无日期观测，未使用零值填充。") } }
            ForEach(report.points.sorted { $0.date == $1.date ? $0.seriesID < $1.seriesID : $0.date < $1.date }) { point in
                Section(DemoFormat.dateRange(start: point.date, end: point.date)) {
                    Text(DemoFormat.numbered("方案", point.planNumber))
                    DemoValueRow(title: metric.rawValue, value: metric.display(point.values, completion: report.completion))
                    Text("批次：\(point.seriesID)").font(.footnote).foregroundStyle(.secondary)
                    if metric == .conversion {
                        let operands = metric.operands(point.values)
                        DemoValueRow(title: "成交／触达", value: "\(operands.0) ÷ \(operands.1)")
                    }
                }
            }
        }
        .navigationTitle("日期读数 · \(metric.unit)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AnalyticsTrendDetailView: View {
    let report: AnalyticsReport
    @State var metric: AnalyticsMetric
    var body: some View {
        DemoPage {
            Text(report.query.period.range.label).font(DemoTheme.Typography.caption)
            AnalyticsTrendView(report: report, metric: $metric)
        }
        .navigationTitle("趋势图")
        .navigationBarTitleDisplayMode(.inline)
    }
}
