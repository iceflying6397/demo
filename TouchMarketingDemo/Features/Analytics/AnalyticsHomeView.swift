import SwiftUI

struct AnalyticsHomeView: View {
    let store: MockDataStore
    @Environment(\.analyticsIntegration) private var integration
    @State private var selection = AnalyticsSelection()
    @State private var metric: AnalyticsMetric = .conversion
    @State private var showingFilter = false
    @State private var batchID: String?
    @State private var loadMessage: String?
    private var report: AnalyticsReport {
        if let batchID, let integration { return integration.statistics.report(batchID: batchID, query: selection.query) }
        return AnalyticsFixtures.historical(selection.query, store: store)
    }
    var body: some View {
        DemoPage {
            Text("相同时间范围的营销效果 · 本地模拟").font(DemoTheme.Typography.body)
            Picker("时间范围", selection: $selection.period) {
                ForEach(AnalyticsPeriod.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu).accessibilityIdentifier("analytics.period")
            AnalyticsScopeHeader(report: report)
            Button("筛选时间、人群与方案") { showingFilter = true }
                .buttonStyle(DemoSecondaryButtonStyle()).accessibilityIdentifier("analytics.filter")
            if report.completion == .noMatch {
                DemoEmptyState(title: "无匹配数据", message: report.explanation)
                Button("清除筛选，回到历史主样本") { restoreDefault() }
                    .buttonStyle(DemoPrimaryButtonStyle())
            } else {
                AnalyticsMetricsCard(values: report.totals, completion: report.completion)
                NavigationLink("查看派生指标与公式") {
                    AnalyticsMetricDetailView(values: report.totals, completion: report.completion,
                                              range: report.query.period.range, source: report.explanation)
                }.buttonStyle(DemoSecondaryButtonStyle()).accessibilityIdentifier("analytics.metrics.detail")
                AnalyticsTrendView(report: report, metric: $metric)
                NavigationLink("展开趋势图与日期读数") { AnalyticsTrendDetailView(report: report, metric: metric) }
                    .buttonStyle(DemoSecondaryButtonStyle())
                AnalyticsComparisonView(report: report)
                NavigationLink(report.isSameGroup ? "查看同组方案对比与快照" : "查看跨任务比较与快照") {
                    AnalyticsDetailView(report: report)
                }.buttonStyle(DemoPrimaryButtonStyle()).accessibilityIdentifier("analytics.detail")
            }
            DemoCard {
                Text("模拟发送批次").font(DemoTheme.Typography.heading)
                if let integration {
                    if integration.statistics.batches.isEmpty { Text("尚无新批次，请在发送审批页确认模拟发送。") }
                    ForEach(integration.statistics.batches.values.sorted { $0.id < $1.id }) { batch in
                        Button("查看批次 \(batch.id) · 人群\(batch.audienceNumber)") {
                            batchID = batch.id
                            selection.audienceID = batch.audienceID
                            selection.planIDs = batch.groups.map(\.planID)
                        }.buttonStyle(DemoSecondaryButtonStyle())
                    }
                    if let batchID {
                        Button(integration.statistics.loaded[batchID] == nil ? "载入本批次模拟统计" : "已载入 · 再次载入校验") {
                            let wasLoaded = integration.statistics.loaded[batchID] != nil
                            loadMessage = integration.loadStatistics(batchID) ? "已载入匹配的模拟统计。" : wasLoaded ? "已载入，重复操作未新增结果。" : "该批次配置暂无匹配模拟统计，继续统计中。"
                        }.buttonStyle(DemoSecondaryButtonStyle())
                        if let loadMessage { Text(loadMessage).font(DemoTheme.Typography.caption) }
                        Text("仅匹配业务日、人群／方案版本、分配与成功范围的fixture可载入。无匹配继续统计中；重复载入不累加。")
                            .font(DemoTheme.Typography.caption)
                        Button("回到历史主样本") { restoreDefault() }.buttonStyle(DemoSecondaryButtonStyle())
                    }
                } else {
                    Text("新的模拟发送尚未接入。当前可查看完整历史样本及独立边界演示。")
                        .font(DemoTheme.Typography.caption)
                }
                NavigationLink("验证边界状态与批次契约") { AnalyticsBoundaryView() }
                    .buttonStyle(DemoSecondaryButtonStyle()).accessibilityIdentifier("analytics.boundary")
            }
            DemoCard {
                Text("统计口径").font(DemoTheme.Typography.heading)
                Text(report.deduplication).font(DemoTheme.Typography.caption)
                Text("固定参考日2026/10/11 · Asia/Shanghai。结束边界为10/12 00:00，不含结束时刻。按统计业务日期筛选；实际操作时间不改变范围。历史记录保留发送版本，归因与退款口径待统一。")
                    .font(DemoTheme.Typography.caption)
                Text("AI建议在对应人群／方案Tab查看；数据页不修改建议或方案。")
                    .font(DemoTheme.Typography.caption)
            }
        }
        .navigationTitle("数据")
        .sheet(isPresented: $showingFilter) {
            AnalyticsFilterView(store: store, apply: { selection = $0 }, draft: selection)
        }
        .onChange(of: integration?.resetGeneration) { _, _ in
            restoreDefault(); metric = .conversion; showingFilter = false
        }
    }
    private func restoreDefault() { selection = AnalyticsSelection(); batchID = nil; loadMessage = nil }
}
