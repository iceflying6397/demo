import SwiftUI

struct AnalyticsDetailView: View {
    let report: AnalyticsReport
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        DemoPage {
            AnalyticsScopeHeader(report: report)
            DemoCard {
                Text(report.isSameGroup ? "同组测试，客户互斥" : "同时间跨任务比较").font(DemoTheme.Typography.heading)
                Text(report.deduplication).font(DemoTheme.Typography.caption)
                if !report.isSameGroup {
                    Text("包含多次触达；不同人群、批次与版本的条件可能不同，不视为完全可比。")
                        .font(DemoTheme.Typography.caption)
                }
            }
            AnalyticsComparisonView(report: report)
            ForEach(report.performances) { performance in
                NavigationLink {
                    AnalyticsSnapshotView(performance: performance, range: report.query.period.range, completion: report.completion)
                } label: {
                    DemoCard {
                        Text("\(performance.planName) · V\(performance.planVersion)").font(DemoTheme.Typography.heading)
                        Text("\(performance.audienceName) V\(performance.audienceVersion) · 分配\(performance.percentage)%")
                        Text("批次：\(performance.batchID)").font(DemoTheme.Typography.caption)
                        Text("查看发送快照与本批次指标 ›").font(DemoTheme.Typography.caption)
                    }
                }
                .buttonStyle(.plain)
            }
            Button("返回数据首页") { dismiss() }.buttonStyle(DemoSecondaryButtonStyle())
        }
        .navigationTitle(report.isSameGroup ? "同组方案对比" : "跨任务比较")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AnalyticsComparisonView: View {
    let report: AnalyticsReport
    @Environment(\.dynamicTypeSize) private var typeSize
    private var planIDs: [String] { Array(Set(report.performances.map(\.planID))).sorted() }
    var body: some View {
        DemoCard {
            Text("方案对比 · 统一时间范围").font(DemoTheme.Typography.heading)
            if typeSize.isAccessibilitySize {
            // Vertical columns retain all five values at narrow widths / accessibility text sizes.
            ForEach(planIDs, id: \.self) { planID in
                let records = report.performances.filter { $0.planID == planID }
                let versions = Array(Set(records.map(\.planVersion))).sorted().map { "V\($0)" }.joined(separator: "/")
                Text("\(records.first?.planName ?? planID) · 包含\(versions)").font(DemoTheme.Typography.heading)
                ForEach(AnalyticsMetric.chartMetrics) { metric in
                    DemoValueRow(title: metric.rawValue, value: metric.display(AnalyticsFixtures.planTotals(report, planID: planID), completion: report.completion))
                }
            }
            Text("去重合计").font(DemoTheme.Typography.heading)
            ForEach(AnalyticsMetric.chartMetrics) { metric in
                DemoValueRow(title: metric.rawValue, value: metric.display(report.totals, completion: report.completion))
            }
            } else {
                Text("表格可横向滚动；大字体时改为逐方案展开。")
                    .font(DemoTheme.Typography.caption).foregroundStyle(DemoTheme.ColorToken.secondaryText)
                ScrollView(.horizontal) {
                    Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text("指标").gridColumnAlignment(.leading)
                            ForEach(planIDs, id: \.self) { id in
                                let records = report.performances.filter { $0.planID == id }
                                let versions = Array(Set(records.map(\.planVersion))).sorted().map { "V\($0)" }.joined(separator: "/")
                                VStack { Text(records.first?.planName ?? id); Text(versions) }
                            }
                            Text("去重合计")
                        }
                        .font(DemoTheme.Typography.heading)
                        ForEach(AnalyticsMetric.chartMetrics) { metric in
                            GridRow {
                                Text(metric.rawValue)
                                ForEach(planIDs, id: \.self) { id in
                                    Text(metric.display(AnalyticsFixtures.planTotals(report, planID: id), completion: report.completion))
                                }
                                Text(metric.display(report.totals, completion: report.completion))
                            }
                            .font(DemoTheme.Typography.caption)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.bottom, 8)
                }
            }
            Text("合计转化率由联合成交人数÷联合触达人数重新计算，不平均方案转化率。固定样本需结合样本量与条件判断。")
                .font(DemoTheme.Typography.caption).foregroundStyle(DemoTheme.ColorToken.secondaryText)
        }
    }
}

struct AnalyticsSnapshotView: View {
    let performance: AnalyticsPerformance
    let range: AnalyticsDateRange
    let completion: AnalyticsCompletion
    var body: some View {
        DemoPage {
            DemoCard {
                Text("\(performance.planName) · V\(performance.planVersion)").font(DemoTheme.Typography.heading)
                Text(range.label)
                DemoValueRow(title: "发送人群版本", value: "\(performance.audienceName) V\(performance.audienceVersion)")
                DemoValueRow(title: "分配比例", value: "\(performance.percentage)%")
                Text("批次：\(performance.batchID)")
                Text("业务日期：\(DemoFormat.dateRange(start: performance.businessDate, end: performance.businessDate))")
                Text(performance.sourceSnapshot ?? "发送时内容快照缺失；未以最新版内容替代。")
                    .font(DemoTheme.Typography.body)
            }
            AnalyticsMetricsCard(values: performance.values, completion: completion)
            NavigationLink("查看本批次指标公式") {
                AnalyticsMetricDetailView(values: performance.values, completion: completion,
                                          range: range, source: "批次\(performance.batchID) · \(performance.planName) V\(performance.planVersion)")
            }.buttonStyle(DemoSecondaryButtonStyle())
        }
        .navigationTitle("发送版本快照")
        .navigationBarTitleDisplayMode(.inline)
    }
}
