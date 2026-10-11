import SwiftUI

struct ApprovalRetryConfirmView: View {
    let batchID: String
    @Environment(DemoSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var preset: RetryPreset = .allSucceeded
    @State private var message: String?

    var body: some View {
        DemoPage {
            Text("只重试尚未成功的范围，沿用原快照、原版本和原分组。")
                .font(DemoTheme.Typography.body)
            if let batch = session.batch(id: batchID), let snapshot = session.snapshot(for: batch.taskID) {
                DemoCard {
                    DemoValueRow(title: "批次", value: batch.id)
                    DemoValueRow(title: "当前状态", value: batch.status.rawValue)
                    DemoValueRow(title: "已成功", value: "\(DemoFormat.count(batch.succeededTotal)) 人")
                    DemoValueRow(title: "失败范围", value: "\(DemoFormat.count(batch.failedTotal)) 人")
                    ForEach(Array(snapshot.groups.enumerated()), id: \.offset) { index, group in
                        let count = batch.groups.first { $0.planID == group.planID }
                        Text("\(ApprovalDisplay.letter(index)) 组 · \(group.displayName) · V\(group.planVersion)")
                            .font(DemoTheme.Typography.heading)
                        DemoValueRow(title: "失败", value: "\(DemoFormat.count(count?.failed ?? 0)) 人")
                        DemoValueRow(
                            title: "当前资源",
                            value: session.isResourceValid(planID: group.planID) ? "有效" : (session.resourceInvalidReason(planID: group.planID) ?? "已失效")
                        )
                    }
                }
                Text("演示控制：选择这次重试的确定结果。取消不会记次数，也不会改人数。")
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                Picker("重试结果", selection: $preset) {
                    Text(RetryPreset.allSucceeded.rawValue).tag(RetryPreset.allSucceeded)
                    if batch.groups.contains(where: { $0.failed >= 2 }) {
                        Text(RetryPreset.stillPartial.rawValue).tag(RetryPreset.stillPartial)
                    }
                }
                .pickerStyle(.segmented)
                if batch.groups.allSatisfy({ $0.failed < 2 }) {
                    Text("失败人数不足 2，只提供全部补发成功。")
                        .font(DemoTheme.Typography.caption)
                        .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                }
                Button("确认重试") {
                    let result = session.startRetry(batchID: batchID, preset: preset)
                    message = result.message
                    if case .saved = result { dismiss() }
                }
                .buttonStyle(DemoPrimaryButtonStyle())
            } else {
                DemoEmptyState(title: "没有可重试的批次", message: "请从发送结果进入。")
            }
            if let message {
                Text(message)
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
            }
            Button("取消") { dismiss() }.buttonStyle(DemoSecondaryButtonStyle())
        }
        .navigationTitle("重试确认")
        .navigationBarTitleDisplayMode(.inline)
    }
}
