import SwiftUI

struct PlanRulePreviewView: View {
    let store: MockDataStore
    let rule: TouchRule
    let isDraft: Bool
    @Environment(\.planSession) private var session
    @State private var shownPreview: PlanRulePreview?
    @State private var errors: [String] = []
    @State private var confirmGeneration = false
    private var context: PlanContext { .init(store: store, session: session) }
    private var generation: PlanRuleGeneration? {
        guard let shownPreview else { return nil }
        return context.generations.first { $0.id == shownPreview.deduplicationKey }
    }

    var body: some View {
        DemoPage {
            Text(isDraft ? "未保存草稿 · 只读预览" : "本地模拟范围 · 生成后仍需人工审批")
            if let preview = shownPreview {
                PlanRulePreviewContent(preview: preview)
                if let generation {
                    DemoEmptyState(title: "本周期已生成", message: "\(DemoFormat.numbered("任务", generation.taskNumber))，生成于 \(PlanPresentation.timestamp(generation.createdAt))。请到发送审批查看。")
                } else if !preview.rule.configuration.isEnabled {
                    Text("规则已禁用，不生成任务。")
                } else if preview.expectedReach == 0 {
                    DemoEmptyState(title: "没有匹配客户", message: "本周期不生成空任务。")
                } else if isDraft {
                    Text("请先保存规则，再从规则列表预览并生成。")
                } else if session?.ruleGenerationAvailable != true {
                    DemoEmptyState(title: "任务生成尚未接通", message: "当前预览未创建待审批任务。")
                } else {
                    Button("确认生成模拟待审批…") { confirmGeneration = true }
                        .buttonStyle(DemoPrimaryButtonStyle())
                }
            }
            PlanErrorsView(messages: errors)
            Button("重新核对预览", action: refresh).buttonStyle(DemoSecondaryButtonStyle())
        }
        .navigationTitle("规则预览").navigationBarTitleDisplayMode(.inline)
        .onAppear { if shownPreview == nil { refresh() } }
        .confirmationDialog("仅生成待审批任务，不发送消息。", isPresented: $confirmGeneration, titleVisibility: .visible) {
            Button("生成待审批任务", action: generate)
            Button("取消", role: .cancel) { }
        }
    }

    private func refresh() {
        do {
            let current: TouchRule
            if isDraft { current = rule }
            else if let found = context.rules.first(where: { $0.id == rule.id }) { current = found }
            else { throw PlanValidationError("规则不可用，请返回列表。") }
            shownPreview = try context.preview(rule: current)
            errors = []
        } catch { shownPreview = nil; errors = [error.localizedDescription] }
    }

    private func generate() {
        guard !isDraft, let session, let shownPreview else { return }
        do {
            guard let rule = context.rules.first(where: { $0.id == shownPreview.rule.id }) else {
                throw PlanValidationError("规则已不存在，请重新预览。")
            }
            try PlanValidation.validateGeneration(preview: shownPreview, current: context.preview(rule: rule), generations: context.generations)
            _ = try session.generatePendingTask(from: shownPreview)
            // 成功状态来自共享会话的真实生成记录，不能在页面设一个成功布尔值。
            errors = []
        } catch { errors = [error.localizedDescription] }
    }
}

struct PlanRulePreviewContent: View {
    let preview: PlanRulePreview
    var body: some View {
        DemoCard {
            DemoValueRow(title: "任务来源", value: preview.rule.configuration.kind.rawValue)
            DemoValueRow(title: "演示参考日", value: preview.cycleID + "（上海）")
            DemoValueRow(title: "卡片生成时间", value: preview.rule.configuration.timeLabel)
            Text(preview.rule.configuration.conditionLabel)
            if let cutoff = preview.cutoffDate { DemoValueRow(title: "最近购买日期不晚于", value: PlanPresentation.timestamp(cutoff)) }
            Text(preview.scopeSummary)
            DemoValueRow(title: "预设范围", value: "\(preview.audience.displayName) · V\(preview.audience.version)")
            DemoValueRow(title: "去重后预计人数", value: "\(DemoFormat.count(preview.expectedReach)) 人")
        }
        ForEach(Array(preview.allocation.groups.enumerated()), id: \.element.id) { index, group in
            if let snapshot = preview.plans.first(where: { $0.plan.id == group.planID }) {
                DemoCard {
                    Text("\(snapshot.plan.displayName) · V\(group.planVersion)").font(DemoTheme.Typography.heading)
                    DemoValueRow(title: "分配", value: "\(group.percentage)%")
                    DemoValueRow(title: "预计人数", value: "\(preview.allocation.expectedCounts(total: preview.expectedReach)[index]) 人")
                    Text(snapshot.plan.message)
                    DemoValueRow(title: "资源", value: snapshot.resource?.name ?? "无搭配资源")
                }
            }
        }
    }
}

struct PlanRuleGenerationListView: View {
    let store: MockDataStore
    let ruleID: String
    @Environment(\.planSession) private var session
    var body: some View {
        DemoPage {
            let records = PlanContext(store: store, session: session).generations
                .filter { $0.preview.rule.id == ruleID }.sorted { $0.createdAt > $1.createdAt }
            ForEach(records) { record in
                DemoCard {
                    Text(DemoFormat.numbered("任务", record.taskNumber)).font(DemoTheme.Typography.title)
                    DemoValueRow(title: "生成时间", value: PlanPresentation.timestamp(record.createdAt))
                    Text("生成时冻结配置；审批当前处理状态请到发送审批查看。")
                }
                PlanRulePreviewContent(preview: record.preview)
            }
            if records.isEmpty { DemoEmptyState(title: "尚无生成记录", message: "取消预览、禁用规则、空范围均不会生成任务。") }
        }.navigationTitle("生成记录").navigationBarTitleDisplayMode(.inline)
    }
}
