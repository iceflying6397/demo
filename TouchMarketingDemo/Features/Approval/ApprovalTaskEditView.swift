import SwiftUI

struct ApprovalTaskEditView: View {
    let taskID: String
    @Environment(DemoSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ApprovalFormDraft?
    @State private var message: String?
    @State private var loaded = false

    var body: some View {
        DemoPage {
            if let task = session.task(id: taskID),
               task.approvalStatus == .confirmed || task.approvalStatus == .rejected {
                DemoEmptyState(title: "不能调整", message: "已确认或已拒绝的任务不能再进入可写调整。")
            } else if let task = session.task(id: taskID), let draftBinding {
                Text("未点保存不会改任务。确认发送只用已保存配置。")
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                DemoCard {
                    DemoValueRow(title: "当前人群", value: audienceName(draftBinding.wrappedValue))
                    NavigationLink("更换人群") { ApprovalAudiencePickerView(draft: draftBinding) }
                        .buttonStyle(DemoSecondaryButtonStyle())
                    if let audience = session.audienceRevision(id: draftBinding.wrappedValue.audienceID, version: draftBinding.wrappedValue.audienceVersion),
                       audience.hasInsufficientEvidence {
                        Text("所选人群有评分依据不足。这不是零覆盖。")
                            .font(DemoTheme.Typography.caption)
                            .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                    }
                }
                DemoCard {
                    ForEach(Array(draftBinding.wrappedValue.slots.enumerated()), id: \.offset) { index, _ in
                        NavigationLink("更换\(ApprovalDisplay.letter(index))组方案") {
                            ApprovalPlanPickerView(draft: draftBinding, slotIndex: index)
                        }
                        .buttonStyle(DemoSecondaryButtonStyle())
                    }
                    ApprovalAllocationEditor(
                        draft: draftBinding,
                        reach: session.adjustmentReach(
                            taskID: taskID,
                            audienceID: draftBinding.wrappedValue.audienceID,
                            version: draftBinding.wrappedValue.audienceVersion
                        ),
                        recommendation: recommendation(task),
                        planName: planName,
                        onRestore: { restore(task) },
                        onAddSecond: addSecond,
                        onRemoveLast: removeLast
                    )
                }
                if let message {
                    Text(message)
                        .font(DemoTheme.Typography.caption)
                        .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                }
                Button("保存") { save(task) }
                    .buttonStyle(DemoPrimaryButtonStyle())
                    .accessibilityIdentifier("approval.save")
            } else {
                DemoEmptyState(title: "任务不可用", message: "没有找到这条任务。")
            }
            Button("取消") { dismiss() }.buttonStyle(DemoSecondaryButtonStyle())
        }
        .navigationTitle("调整发送任务")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadIfNeeded)
    }

    private var draftBinding: Binding<ApprovalFormDraft>? {
        guard let draft else { return nil }
        return Binding(
            get: { self.draft ?? draft },
            set: { self.draft = $0 }
        )
    }

    private func loadIfNeeded() {
        guard !loaded, let task = session.task(id: taskID) else { return }
        draft = .from(task: task)
        loaded = true
    }

    private func save(_ task: ApprovalTask) {
        guard let draft else { return }
        let reach = session.adjustmentReach(taskID: taskID, audienceID: draft.audienceID, version: draft.audienceVersion)
        if let error = draft.validationMessage(reach: reach) {
            message = error
            return
        }
        guard let allocation = draft.makeAllocation() else {
            message = "分配无效，不能保存。"
            return
        }
        let result = session.saveAdjustment(
            taskID: task.id, audienceID: draft.audienceID,
            audienceVersion: draft.audienceVersion, allocation: allocation
        )
        message = result.message
        if case .saved = result { dismiss() }
    }

    private func restore(_ task: ApprovalTask) {
        guard var draft else { return }
        draft.slots = task.recommendedAllocation.groups.map {
            .init(planID: $0.planID, planVersion: $0.planVersion)
        }
        draft.primaryPercentText = task.recommendedAllocation.groups.first.map { String($0.percentage) } ?? "100"
        self.draft = draft
        message = "草稿已回到推荐比例。保存后才会写入任务。"
    }

    private func addSecond() {
        guard var draft, draft.slots.count == 1, let first = draft.slots.first else { return }
        guard let other = session.plans.first(where: { $0.id != first.planID }) else {
            message = "没有另一套可添加的方案。"
            return
        }
        draft.slots.append(.init(planID: other.id, planVersion: other.version))
        draft.primaryPercentText = "50"
        self.draft = draft
        message = "已加入第二套方案，初始 50%／50%。可以继续调整。"
    }

    private func removeLast() {
        guard var draft, draft.slots.count > 1 else { return }
        draft.slots.removeLast()
        draft.primaryPercentText = "100"
        self.draft = draft
        message = "已保留一套方案，比例为 100%。"
    }

    private func audienceName(_ draft: ApprovalFormDraft) -> String {
        session.audienceRevision(id: draft.audienceID, version: draft.audienceVersion)?.displayName ?? "人群不可用"
    }

    private func planName(_ id: String, _ version: Int) -> String {
        session.planRevision(id: id, version: version)?.displayName ?? "方案不可用"
    }

    private func recommendation(_ task: ApprovalTask) -> String {
        task.recommendedAllocation.groups.enumerated().map { index, group in
            "\(ApprovalDisplay.letter(index)) \(group.percentage)%"
        }.joined(separator: "／")
    }
}
