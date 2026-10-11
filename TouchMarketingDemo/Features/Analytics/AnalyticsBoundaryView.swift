import SwiftUI

/// Isolated fixture harness, not an approval sender or an alternative session.
/// The exact reducer and matching logic here are what A owns in DemoSession.
struct AnalyticsBoundaryView: View {
    @State private var boundary: AnalyticsFixtures.Boundary = .pending
    @State private var metric: AnalyticsMetric = .conversion
    @State private var callbacks = AnalyticsBatchStatistics()
    @State private var message = "尚未应用回调样本。"
    private var report: AnalyticsReport { AnalyticsFixtures.boundary(boundary) }
    var body: some View {
        DemoPage {
            Text("独立契约验证 · 不发起审批、不发送消息，不加入历史或共享会话。")
                .font(DemoTheme.Typography.caption)
            Picker("边界样本", selection: $boundary) {
                ForEach(AnalyticsFixtures.Boundary.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("analytics.boundary.state")
            AnalyticsScopeHeader(report: report)
            AnalyticsMetricsCard(values: report.totals, completion: report.completion)
            AnalyticsTrendView(report: report, metric: $metric)
            NavigationLink("查看此状态指标明细") {
                AnalyticsMetricDetailView(values: report.totals, completion: report.completion,
                                          range: report.query.period.range, source: report.explanation)
            }.buttonStyle(DemoSecondaryButtonStyle())
            DemoCard {
                Text("C → D 批次契约验证").font(DemoTheme.Typography.heading)
                Text("确定的50/50回调样本：首次唯一成功900/950，重试完成后1000/1000。同一个批次，不新增重复触达。")
                    .font(DemoTheme.Typography.caption)
                Button("应用部分失败回调样本") {
                    message = callbacks.receive(AnalyticsFixtures.callback(retried: false)) ? "已接收：唯一成功1850人，成交统计中。" : "重复或旧回调已忽略。"
                }.buttonStyle(DemoSecondaryButtonStyle()).accessibilityIdentifier("analytics.callback.partial")
                Button("应用重试完成回调样本") {
                    message = callbacks.receive(AnalyticsFixtures.callback(retried: true)) ? "同批次更新：唯一成功2000人，成交统计中。" : "重复或旧回调已忽略。"
                }.buttonStyle(DemoSecondaryButtonStyle()).accessibilityIdentifier("analytics.callback.retry")
                Button("载入匹配模拟统计") {
                    message = callbacks.load(batchID: "fixture-new-batch") ? "已载入唯一结果：130人成交；未覆盖历史。" : "已载入或配置无匹配；没有新增结果。"
                }.buttonStyle(DemoSecondaryButtonStyle()).accessibilityIdentifier("analytics.callback.load")
                Text(message).font(DemoTheme.Typography.caption).accessibilityIdentifier("analytics.callback.result")
                if !callbacks.batches.isEmpty {
                    let result = callbacks.report(batchID: "fixture-new-batch", query: AnalyticsSelection().query)
                    AnalyticsMetricsCard(values: result.totals, completion: result.completion)
                    NavigationLink("查看该回调批次与版本") { AnalyticsDetailView(report: result) }
                        .buttonStyle(DemoSecondaryButtonStyle())
                }
                Button("清除契约演示状态") { callbacks.reset(); message = "契约样本已清除；共享统一重置需 A 接线。" }
                    .buttonStyle(DemoSecondaryButtonStyle())
            }
        }
        .navigationTitle("边界与批次契约")
        .navigationBarTitleDisplayMode(.inline)
    }
}
