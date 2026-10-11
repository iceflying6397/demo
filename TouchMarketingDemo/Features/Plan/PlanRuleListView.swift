import SwiftUI

struct PlanRuleListView: View {
    let store: MockDataStore
    @Environment(\.planSession) private var session
    @State private var errors: [String] = []
    private var context: PlanContext { .init(store: store, session: session) }

    var body: some View {
        DemoPage {
            Text("规则只生成待审批安排，每次发送都需要人工确认。")
            NavigationLink("新建生日规则") { PlanRuleEditView(store: store, rule: nil, kind: .birthday) }
                .buttonStyle(DemoPrimaryButtonStyle())
            NavigationLink("新建定期回访规则") { PlanRuleEditView(store: store, rule: nil, kind: .followUp) }
                .buttonStyle(DemoSecondaryButtonStyle())
            PlanErrorsView(messages: errors)
            if context.rules.isEmpty { DemoEmptyState(title: "暂无触达规则", message: "新建生日或回访规则，保存后预览。") }
            ForEach(context.rules.sorted { $0.number < $1.number }) { rule in
                DemoCard {
                    Text("\(rule.displayName) · \(rule.configuration.kind.rawValue)").font(DemoTheme.Typography.heading)
                    DemoValueRow(title: "状态", value: rule.configuration.isEnabled ? "已启用" : "已禁用")
                    Text(rule.configuration.conditionLabel)
                    DemoValueRow(title: "卡片生成时间", value: rule.configuration.timeLabel + "（上海）")
                    PlanRuleAllocationSummary(configuration: rule.configuration, plans: context.plans)
                    let generations = context.generations.filter { $0.preview.rule.id == rule.id }.sorted { $0.createdAt > $1.createdAt }
                    if let last = generations.first {
                        DemoValueRow(title: "最近生成", value: "\(DemoFormat.numbered("任务", last.taskNumber)) · \(PlanPresentation.timestamp(last.createdAt))")
                        Text("待审批已创建；审批处理状态请到发送审批查看。")
                        NavigationLink("查看生成记录与冻结配置") { PlanRuleGenerationListView(store: store, ruleID: rule.id) }
                    } else { Text("最近生成：尚未生成") }
                    NavigationLink("编辑配置") { PlanRuleEditView(store: store, rule: rule, kind: rule.configuration.kind) }
                    NavigationLink("预览并生成模拟待审批") { PlanRulePreviewView(store: store, rule: rule, isDraft: false) }
                        .buttonStyle(DemoSecondaryButtonStyle())
                    if session != nil {
                        Button(rule.configuration.isEnabled ? "禁用规则" : "启用规则") {
                            do { try session?.setTouchRuleEnabled(id: rule.id, baseRevision: rule.revision, enabled: !rule.configuration.isEnabled) }
                            catch { errors = [error.localizedDescription] }
                        }
                    }
                }
            }
            if session == nil { PlanConnectionNotice() }
        }.navigationTitle("触达规则").navigationBarTitleDisplayMode(.inline)
    }
}

struct PlanRuleAllocationSummary: View {
    let configuration: TouchRuleConfiguration
    let plans: [MarketingPlan]
    var body: some View {
        DemoValueRow(title: "方案 A", value: label(configuration.primaryPlanID) + " · \(configuration.primaryPercentage)%")
        if let id = configuration.secondaryPlanID {
            DemoValueRow(title: "方案 B", value: label(id) + " · \(100 - configuration.primaryPercentage)%")
        }
    }
    private func label(_ id: String) -> String { plans.first { $0.id == id }?.displayName ?? "方案不可用" }
}
