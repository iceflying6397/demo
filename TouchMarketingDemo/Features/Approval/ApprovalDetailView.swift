import SwiftUI

struct ApprovalDetailView: View {
    let taskID: String
    @Environment(DemoSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DemoPage {
            if let task = session.task(id: taskID) {
                Text("这里是已保存配置。未保存的首页草稿不会出现在本页，确认发送也不使用草稿。")
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                if let snapshot = session.snapshot(for: taskID) {
                    DemoCard {
                        Text("已按发送快照冻结").font(DemoTheme.Typography.heading)
                        DemoValueRow(title: "人群", value: "\(snapshot.audienceDisplayName) V\(snapshot.audienceVersion)")
                        DemoValueRow(title: "本次预计", value: "\(DemoFormat.count(snapshot.expectedReach)) 人")
                        ForEach(Array(snapshot.groups.enumerated()), id: \.offset) { index, group in
                            DemoValueRow(
                                title: "\(ApprovalDisplay.letter(index)) \(group.displayName)",
                                value: "V\(group.planVersion) · \(group.percentage)%"
                            )
                        }
                    }
                } else {
                    savedCard(task)
                }
                if task.approvalStatus == .rejected {
                    DemoEmptyState(title: "已拒绝", message: "没有发送批次。完整经过可在处理记录里查看。")
                } else if task.approvalStatus == .confirmed {
                    NavigationLink("查看发送结果") { ApprovalResultView(taskID: taskID) }
                        .buttonStyle(DemoPrimaryButtonStyle())
                } else {
                    ApprovalPendingActions(taskID: taskID, hasUnsavedDraft: false)
                }
                NavigationLink("处理记录") { ApprovalRecordListView(taskID: taskID) }
                    .buttonStyle(DemoSecondaryButtonStyle())
            } else {
                DemoEmptyState(title: "任务不可用", message: "没有找到这条任务。")
            }
            Button("返回发送审批首页") { dismiss() }.buttonStyle(DemoSecondaryButtonStyle())
        }
        .navigationTitle(session.task(id: taskID)?.displayName ?? "任务")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func savedCard(_ task: ApprovalTask) -> some View {
        DemoCard {
            DemoValueRow(title: "状态", value: task.approvalStatus.rawValue)
            DemoValueRow(title: "来源", value: task.sourceMark)
            let audience = session.audienceRevision(id: task.audienceID, version: task.audienceVersion)
            DemoValueRow(title: "人群", value: audience?.displayName ?? "人群不可用")
            DemoValueRow(title: "人群版本", value: "V\(task.audienceVersion)")
            DemoValueRow(title: "人群覆盖", value: audience.map { "\(DemoFormat.count($0.memberCount)) 人" } ?? "不可用")
            DemoValueRow(title: "本次预计", value: ApprovalDisplay.reachText(for: task))
            if let audience {
                ForEach(Array(audience.scores.prefix(3))) { score in
                    DemoValueRow(title: score.dimension.rawValue, value: score.displayValue)
                }
            }
            ForEach(Array(task.allocation.groups.enumerated()), id: \.offset) { index, group in
                let plan = session.planRevision(id: group.planID, version: group.planVersion)
                Text("\(ApprovalDisplay.letter(index)) 组 · \(plan?.displayName ?? "方案不可用") · V\(group.planVersion)")
                    .font(DemoTheme.Typography.heading)
                DemoValueRow(title: "目的", value: plan?.purpose.rawValue ?? "—")
                DemoValueRow(title: "适用客户", value: plan?.customerStage.rawValue ?? "—")
                DemoValueRow(title: "比例", value: "\(group.percentage)%")
                if task.reachState == .known {
                    let counts = task.allocation.expectedCounts(total: task.expectedReach)
                    if counts.indices.contains(index) {
                        DemoValueRow(title: "预计人数", value: "\(DemoFormat.count(counts[index])) 人")
                    }
                }
            }
            Text("最多两套方案，每位客户只接收其中一套。")
                .font(DemoTheme.Typography.caption)
                .foregroundStyle(DemoTheme.ColorToken.secondaryText)
        }
    }
}
