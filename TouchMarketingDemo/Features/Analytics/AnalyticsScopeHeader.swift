import SwiftUI

struct AnalyticsScopeHeader: View {
    let report: AnalyticsReport
    var body: some View {
        DemoCard {
            Text(report.query.period.rawValue).font(DemoTheme.Typography.heading)
            Text(report.query.period.range.label).font(DemoTheme.Typography.body)
            DemoValueRow(title: "人群", value: report.query.audienceID.map { id in
                report.performances.first { $0.audienceID == id }?.audienceName ?? (id == "audience-01" ? "人群 01" : id == "audience-02" ? "人群 02" : "人群不可用（\(id)）")
            } ?? "全部人群")
            DemoValueRow(title: "方案", value: report.query.planIDs.isEmpty ? "不指定 · 当前范围合计" : report.query.planIDs.map { id in
                report.performances.first { $0.planID == id }?.planName ?? (id == "plan-01" ? "方案 01" : id == "plan-02" ? "方案 02" : id == "plan-03" ? "方案 03" : "方案不可用（\(id)）")
            }.joined(separator: "／"))
            Text("\(report.completion.rawValue) · 本地确定样本").font(DemoTheme.Typography.heading)
            Text(report.explanation).font(DemoTheme.Typography.caption).foregroundStyle(DemoTheme.ColorToken.secondaryText)
        }
    }
}

struct AnalyticsMetricsCard: View {
    let values: AnalyticsValues
    let completion: AnalyticsCompletion
    var body: some View {
        DemoCard {
            Text("效果摘要").font(DemoTheme.Typography.heading)
            ForEach(AnalyticsMetric.chartMetrics) { metric in
                DemoValueRow(title: metric.rawValue, value: metric.display(values, completion: completion))
                    .accessibilityIdentifier("analytics.metric.\(metric.id)")
            }
        }
    }
}
