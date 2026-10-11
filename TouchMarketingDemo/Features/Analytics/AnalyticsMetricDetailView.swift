import SwiftUI

struct AnalyticsMetricDetailView: View {
    let values: AnalyticsValues
    let completion: AnalyticsCompletion
    let range: AnalyticsDateRange
    let source: String
    var body: some View {
        List {
            Section("当前统计范围") {
                Text(range.label).font(DemoTheme.Typography.heading)
                Text(source).font(DemoTheme.Typography.caption)
                Text("来源为统一确定样本或模拟成功触达快照；非真实店铺统计。成交归因窗口、退款与正式回流频率待产品统一。")
                    .font(DemoTheme.Typography.caption)
            }
            ForEach(AnalyticsMetric.allCases) { metric in
                Section(metric.rawValue) {
                    DemoValueRow(title: "当前值", value: metric.display(values, completion: completion))
                    DemoValueRow(title: "单位", value: metric.unit)
                    Text(metric.formula).font(DemoTheme.Typography.body)
                    let operands = metric.operands(values)
                    DemoValueRow(title: "分子／原始值", value: operands.0)
                    DemoValueRow(title: "分母", value: operands.1)
                    if metric.value(values) == nil {
                        Text("分母为0显示—；统计中或缺失字段不按0计算。")
                            .font(DemoTheme.Typography.caption).foregroundStyle(DemoTheme.ColorToken.secondaryText)
                    }
                }
            }
            Section("首购／复购转化率暂无该项样本") {
                Text("缺少首购或复购人数与对应触达阶段分母，不能用总转化率冒充。")
                    .font(DemoTheme.Typography.caption)
            }
        }
        .listStyle(.insetGrouped)
        .foregroundStyle(DemoTheme.ColorToken.primaryText)
        .navigationTitle("指标明细与口径")
        .navigationBarTitleDisplayMode(.inline)
    }
}
