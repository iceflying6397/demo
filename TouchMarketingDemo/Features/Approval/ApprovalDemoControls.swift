import SwiftUI

struct ApprovalDemoControls: View {
    @Environment(DemoSession.self) private var session
    @State private var message: String?

    var body: some View {
        DisclosureGroup("演示控制（非生产操作）") {
            VStack(alignment: .leading, spacing: DemoTheme.Spacing.medium) {
                Text("用来准备版本差异、资源失效、规则任务、五种状态和空列表。重置会恢复任务、记录、批次和这份会话里的样本。")
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                control("模拟人群 01 发布新版本") { session.simulateAudienceRevision(id: "audience-01") }
                control("模拟方案 01 发布新版本") { session.simulatePlanRevision(id: "plan-01") }
                control("将方案 02 标为资源失效") { session.setResourceInvalid(planID: "plan-02", invalid: true) }
                control("恢复方案 02 资源有效") { session.setResourceInvalid(planID: "plan-02", invalid: false) }
                control("移除任务 01 引用的旧人群快照") { session.removePinnedAudienceSnapshot(taskID: "task-01") }
                control("断开任务 01 的人群引用") { session.breakAudienceReference(taskID: "task-01") }
                control("生成单方案任务") { session.createSinglePlanSample() }
                control("按生日规则生成本周期任务") { birthdayTask() }
                control("补齐五种发送状态") { session.prepareStatusSamples() }
                control("拒绝全部待审批") { session.rejectAllPending() }
                control("重置演示") { session.reset(); return .saved("已恢复初始任务、记录、批次和样本。") }
                if let message {
                    Text(message)
                        .font(DemoTheme.Typography.caption)
                        .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                }
            }
            .padding(.top, DemoTheme.Spacing.medium)
        }
        .font(DemoTheme.Typography.heading)
    }

    private func control(_ title: String, action: @escaping () -> ApprovalActionResult) -> some View {
        Button(title) { message = action().message }
            .buttonStyle(DemoSecondaryButtonStyle())
    }

    private func birthdayTask() -> ApprovalActionResult {
        guard let audience = session.audience(id: "audience-01"),
              let planA = session.plan(id: "plan-01"),
              let planB = session.plan(id: "plan-02"),
              let reach = session.knownReach(audienceID: audience.id, version: audience.version),
              let allocation = ABAllocation(groups: [
                .init(planID: planA.id, planVersion: planA.version, percentage: 30),
                .init(planID: planB.id, planVersion: planB.version, percentage: 70)
              ]) else {
            return .failed("当前没有可核对的人群或方案，不能生成规则任务。")
        }
        return session.createPendingTask(request: RulePendingTaskRequest(
            ruleID: "rule-birthday-demo", cycleKey: "2026-10-11", origin: .birthdayRule,
            summary: "生日规则 · 参考日 2026/10/11 · 周期 2026-10-11",
            audienceID: audience.id, audienceVersion: audience.version,
            expectedReach: reach, allocation: allocation
        ))
    }
}
