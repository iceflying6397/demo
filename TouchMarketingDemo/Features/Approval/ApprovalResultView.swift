import SwiftUI

struct ApprovalResultView: View {
    let taskID: String
    @Environment(DemoSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        DemoPage {
            Text("本地模拟结果。成功触达不等于成交已经发生。")
                .font(DemoTheme.Typography.body)
            if let task = session.task(id: taskID), let snapshot = session.snapshot(for: taskID), let batch = session.batch(for: taskID) {
                DemoCard {
                    DemoValueRow(title: "任务", value: task.displayName)
                    DemoValueRow(title: "审批", value: task.approvalStatus.rawValue)
                    DemoValueRow(title: "执行", value: batch.status.rawValue)
                    DemoValueRow(title: "批次", value: batch.id)
                    DemoValueRow(title: "统计业务日", value: DemoFormat.day(batch.businessDate))
                    DemoValueRow(title: "确认时间", value: DemoFormat.dateTime(snapshot.confirmedAt))
                    if let finished = batch.finishedAt {
                        DemoValueRow(title: "执行完成", value: DemoFormat.dateTime(finished))
                    }
                    DemoValueRow(title: "重试次数", value: "\(batch.retryCount)")
                    DemoValueRow(title: "成交数据", value: batch.statisticsStatus.rawValue)
                    if let reason = batch.failureReason {
                        DemoValueRow(title: "失败原因", value: reason)
                    }
                }
                snapshotCard(snapshot)
                countsCard(batch)
                dataNote(batch)
                demoControls(batch)
                if canRetry(batch) {
                    NavigationLink("重试失败部分") { ApprovalRetryConfirmView(batchID: batch.id) }
                        .buttonStyle(DemoPrimaryButtonStyle())
                }
                NavigationLink("处理记录") { ApprovalRecordListView(taskID: taskID) }
                    .buttonStyle(DemoSecondaryButtonStyle())
            } else {
                DemoEmptyState(title: "还没有发送结果", message: "确认并模拟发送之后，才会出现快照和批次。")
            }
            if let message {
                Text(message)
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
            }
            Button("返回") { dismiss() }.buttonStyle(DemoSecondaryButtonStyle())
        }
        .navigationTitle("发送结果")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func canRetry(_ batch: DeliveryBatch) -> Bool {
        guard batch.taskID != "task-history-01" else { return false }
        guard batch.status == .partiallyFailed || batch.status == .failed else { return false }
        return batch.failedTotal > 0 && !batch.isRetryInFlight
    }

    private func snapshotCard(_ snapshot: DeliverySnapshot) -> some View {
        DemoCard {
            Text("发送当时快照").font(DemoTheme.Typography.heading)
            DemoValueRow(title: "人群", value: "\(snapshot.audienceDisplayName) V\(snapshot.audienceVersion)")
            DemoValueRow(title: "人群覆盖", value: "\(DemoFormat.count(snapshot.memberCount)) 人")
            DemoValueRow(title: "本次分配", value: "\(DemoFormat.count(snapshot.expectedReach)) 人")
            ForEach(Array(snapshot.scores.prefix(3))) { score in
                DemoValueRow(title: score.dimension.rawValue, value: score.displayValue)
            }
            ForEach(Array(snapshot.groups.enumerated()), id: \.offset) { index, group in
                Text("\(ApprovalDisplay.letter(index)) 组 · \(group.displayName) · V\(group.planVersion)")
                    .font(DemoTheme.Typography.heading)
                DemoValueRow(title: "目的", value: group.purpose.rawValue)
                DemoValueRow(title: "适用客户", value: group.customerStage.rawValue)
                DemoValueRow(title: "比例", value: "\(group.percentage)%")
                DemoValueRow(title: "分配人数", value: "\(DemoFormat.count(group.allocatedCount)) 人")
                Text(group.message).font(DemoTheme.Typography.body)
                Text(group.resourceSummary)
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
            }
            Text(snapshot.dedupNote)
                .font(DemoTheme.Typography.caption)
                .foregroundStyle(DemoTheme.ColorToken.secondaryText)
        }
    }

    private func countsCard(_ batch: DeliveryBatch) -> some View {
        DemoCard {
            Text("执行人数").font(DemoTheme.Typography.heading)
            if batch.status == .waiting || (batch.status == .sending && !batch.isRetryInFlight && batch.succeededTotal == 0 && batch.failedTotal == 0) {
                Text("尚未产生成功或失败人数。")
                    .font(DemoTheme.Typography.body)
            }
            ForEach(Array(batch.groups.enumerated()), id: \.offset) { index, group in
                DemoValueRow(title: "\(ApprovalDisplay.letter(index)) 组分配", value: "\(DemoFormat.count(group.allocated)) 人")
                DemoValueRow(title: "\(ApprovalDisplay.letter(index)) 组已成功", value: "\(DemoFormat.count(group.succeeded)) 人")
                DemoValueRow(title: "\(ApprovalDisplay.letter(index)) 组未成功", value: "\(DemoFormat.count(group.failed)) 人")
            }
            DemoValueRow(title: "唯一成功触达", value: "\(DemoFormat.count(batch.succeededTotal)) 人")
            Text("重试只补失败范围，不会把成功人数加成 3,500。")
                .font(DemoTheme.Typography.caption)
                .foregroundStyle(DemoTheme.ColorToken.secondaryText)
        }
    }

    private func dataNote(_ batch: DeliveryBatch) -> some View {
        DemoCard {
            Text("数据").font(DemoTheme.Typography.heading)
            if batch.statisticsStatus == .historicalSample {
                Text("这条是历史样本，成交已在数据页载入模拟统计。请打开「数据」Tab 查看 2026/10/05—2026/10/11，不要把 168 人成交抄到新批次。")
                    .font(DemoTheme.Typography.body)
            } else {
                Text("本批次触达可以按批次 \(batch.id) 关联。成交还是统计中；没有匹配样本时不显示未知成交，也不写成 0。请到「数据」Tab 查看历史样本，本页不打开数据首页。")
                    .font(DemoTheme.Typography.body)
            }
        }
    }

    @ViewBuilder
    private func demoControls(_ batch: DeliveryBatch) -> some View {
        if batch.taskID != "task-history-01", batch.status == .waiting || batch.status == .sending {
            DemoCard {
                Text("演示控制").font(DemoTheme.Typography.heading)
                Text("不是生产操作。用它推进等待、发送中和预设终态，没有真实队列或随机失败。")
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                if batch.status == .waiting {
                    Picker("预设结果", selection: presetBinding(batch)) {
                        ForEach(DeliveryPreset.allCases, id: \.self) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    Button("推进模拟开始") { message = session.advance(batchID: batch.id).message }
                        .buttonStyle(DemoPrimaryButtonStyle())
                } else {
                    Text(batch.isRetryInFlight ? "重试执行中。结束前不能再开一次重试。" : "发送中。不能再次确认。")
                        .font(DemoTheme.Typography.body)
                    Button("推进模拟结束") { message = session.advance(batchID: batch.id).message }
                        .buttonStyle(DemoPrimaryButtonStyle())
                }
            }
        }
    }

    private func presetBinding(_ batch: DeliveryBatch) -> Binding<DeliveryPreset> {
        Binding(
            get: { session.batch(id: batch.id)?.preset ?? batch.preset },
            set: { newValue in
                message = session.setInitialPreset(batchID: batch.id, preset: newValue).message
            }
        )
    }
}
