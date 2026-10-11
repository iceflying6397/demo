import SwiftUI

struct ApprovalPlanPickerView: View {
    @Binding var draft: ApprovalFormDraft
    let slotIndex: Int
    @Environment(DemoSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        DemoPage {
            Text("只选择本次任务使用的方案版本。不能在这里改话术或资源。")
                .font(DemoTheme.Typography.body)
            if draft.slots.indices.contains(slotIndex) == false {
                DemoEmptyState(title: "分组不存在", message: "请返回调整页重新添加方案。")
            } else {
                ForEach(session.plans.sorted { $0.number < $1.number }) { plan in
                    planCard(plan)
                }
            }
            if let message {
                Text(message)
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
            }
            Button("取消") { dismiss() }.buttonStyle(DemoSecondaryButtonStyle())
        }
        .navigationTitle("选择方案")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func planCard(_ plan: MarketingPlan) -> some View {
        let otherIDs = draft.slots.enumerated().compactMap { index, slot in
            index == slotIndex ? nil : slot.planID
        }
        let blocked = otherIDs.contains(plan.id)
        return DemoCard {
            Text(plan.displayName).font(DemoTheme.Typography.heading)
            DemoValueRow(title: "目的", value: plan.purpose.rawValue)
            DemoValueRow(title: "适用客户", value: plan.customerStage.rawValue)
            DemoValueRow(title: "版本", value: "V\(plan.version)")
            DemoValueRow(title: "资源", value: session.isResourceValid(planID: plan.id) ? "有效" : "已失效")
            Text(plan.message)
                .font(DemoTheme.Typography.body)
            Text(plan.resourceSummary)
                .font(DemoTheme.Typography.caption)
                .foregroundStyle(DemoTheme.ColorToken.secondaryText)
            if blocked {
                Text("另一组已经使用\(plan.displayName)，不能重复选择。")
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                Button("仍选择\(plan.displayName)") {
                    message = "同一方案不能同时放在两个组。"
                }
                .buttonStyle(DemoSecondaryButtonStyle())
            } else {
                Button("选择\(plan.displayName)") {
                    guard draft.slots.indices.contains(slotIndex) else { return }
                    draft.slots[slotIndex] = .init(planID: plan.id, planVersion: plan.version)
                    dismiss()
                }
                .buttonStyle(DemoPrimaryButtonStyle())
            }
        }
    }
}
