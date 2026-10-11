import SwiftUI

struct ApprovalConfirmView: View {
    let taskID: String
    let hasUnsavedDraft: Bool
    @Environment(DemoSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var keepOriginal = false
    @State private var preset: DeliveryPreset = .succeeded
    @State private var message: String?

    var body: some View {
        DemoPage {
            Text("本地模拟发送，不连接企业微信或店铺。这里核对的是已保存配置。")
                .font(DemoTheme.Typography.body)
            if hasUnsavedDraft {
                DemoEmptyState(
                    title: "有未保存草稿",
                    message: "首页的比例草稿还没保存。请先保存或取消。确认不会使用这份草稿。"
                )
            }
            if let task = session.task(id: taskID) {
                if task.approvalStatus == .confirmed || session.snapshot(for: taskID) != nil {
                    DemoEmptyState(title: "已经确认", message: "没有创建第二份快照或批次。")
                    NavigationLink("查看发送结果") { ApprovalResultView(taskID: taskID) }
                        .buttonStyle(DemoPrimaryButtonStyle())
                } else {
                    facts(task)
                    versionSection(task)
                    if let audience = session.audienceRevision(id: task.audienceID, version: task.audienceVersion),
                       audience.hasInsufficientEvidence {
                        Text("评分依据不足，请核对。这不代表零覆盖，也不单独阻止发送。")
                            .font(DemoTheme.Typography.caption)
                            .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                    }
                    let issues = session.confirmIssues(taskID: taskID)
                    ForEach(issues, id: \.self) { issue in
                        Text(issue)
                            .font(DemoTheme.Typography.caption)
                            .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                    }
                    if canSubmit(task, issues: issues) {
                        Text("演示控制：选择推进结束后的预设结果。这不是生产操作。")
                            .font(DemoTheme.Typography.caption)
                            .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                        Picker("预设结果", selection: $preset) {
                            ForEach(DeliveryPreset.allCases, id: \.self) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        Button("确认并模拟发送") { submit() }
                            .buttonStyle(DemoPrimaryButtonStyle())
                            .accessibilityIdentifier("approval.confirm-send")
                    }
                }
            } else {
                DemoEmptyState(title: "任务不可用", message: "没有找到这条任务。")
            }
            if let message {
                Text(message)
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
            }
            Button("取消") { dismiss() }.buttonStyle(DemoSecondaryButtonStyle())
        }
        .navigationTitle("发送确认")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func canSubmit(_ task: ApprovalTask, issues: [String]) -> Bool {
        guard !hasUnsavedDraft, issues.isEmpty else { return false }
        guard task.approvalStatus == .pending || task.approvalStatus == .deferred else { return false }
        let differences = session.versionDifferences(for: task)
        if differences.isEmpty { return true }
        return keepOriginal && session.pinnedContentAvailable(task)
    }

    private func submit() {
        let result = session.confirmSend(
            taskID: taskID, preset: preset, acknowledgeVersionGap: keepOriginal
        )
        message = result.message
    }

    @ViewBuilder
    private func facts(_ task: ApprovalTask) -> some View {
        DemoCard {
            DemoValueRow(title: "任务", value: task.displayName)
            DemoValueRow(title: "来源", value: task.sourceMark)
            if let audience = session.audienceRevision(id: task.audienceID, version: task.audienceVersion) {
                DemoValueRow(title: "人群", value: "\(audience.displayName) V\(audience.version)")
                DemoValueRow(title: "人群覆盖", value: "\(DemoFormat.count(audience.memberCount)) 人")
                ForEach(Array(audience.scores.prefix(3))) { score in
                    DemoValueRow(title: score.dimension.rawValue, value: score.displayValue)
                }
            } else {
                DemoValueRow(title: "人群", value: "旧版本快照缺失")
            }
            DemoValueRow(title: "本次预计", value: ApprovalDisplay.reachText(for: task))
            Text(ApprovalExecutionMath.dedupNote)
                .font(DemoTheme.Typography.caption)
                .foregroundStyle(DemoTheme.ColorToken.secondaryText)
        }
        DemoCard {
            ForEach(Array(task.allocation.groups.enumerated()), id: \.offset) { index, group in
                if let plan = session.planRevision(id: group.planID, version: group.planVersion) {
                    Text("\(ApprovalDisplay.letter(index)) 组 · \(plan.displayName) · V\(plan.version)")
                        .font(DemoTheme.Typography.heading)
                    DemoValueRow(title: "目的", value: plan.purpose.rawValue)
                    DemoValueRow(title: "适用客户", value: plan.customerStage.rawValue)
                    DemoValueRow(title: "比例", value: "\(group.percentage)%")
                    if task.reachState == .known {
                        let counts = task.allocation.expectedCounts(total: task.expectedReach)
                        if counts.indices.contains(index) {
                            DemoValueRow(title: "预计人数", value: "\(DemoFormat.count(counts[index])) 人")
                        }
                    }
                    DemoValueRow(title: "资源", value: session.isResourceValid(planID: plan.id) ? "有效" : "已失效")
                    Text(plan.resourceSummary)
                        .font(DemoTheme.Typography.caption)
                        .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                } else {
                    Text("\(ApprovalDisplay.letter(index)) 组方案快照缺失")
                }
            }
        }
    }

    @ViewBuilder
    private func versionSection(_ task: ApprovalTask) -> some View {
        let differences = session.versionDifferences(for: task)
        DemoCard {
            Text("版本核对").font(DemoTheme.Typography.heading)
            if differences.isEmpty {
                Text("任务引用的版本就是当前版本。")
                    .font(DemoTheme.Typography.body)
            } else {
                ForEach(differences, id: \.self) { line in
                    Text(line).font(DemoTheme.Typography.body)
                }
                if session.pinnedContentAvailable(task) {
                    Button(keepOriginal ? "已选择继续原版本" : "继续原版本") {
                        keepOriginal = true
                        message = "将按任务里保存的旧版本发送。资源失效仍然会阻止。"
                    }
                    .buttonStyle(DemoSecondaryButtonStyle())
                } else {
                    Text("没有可解析的旧版本快照。不能继续原版本，也不会用最新内容冒充旧版。")
                        .font(DemoTheme.Typography.caption)
                        .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                }
                Button("更新任务到当前版本并重新核对") {
                    keepOriginal = false
                    message = session.updateToCurrentVersions(taskID: taskID).message
                }
                .buttonStyle(DemoSecondaryButtonStyle())
            }
        }
    }
}
