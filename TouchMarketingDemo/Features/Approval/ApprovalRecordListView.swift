import SwiftUI

struct ApprovalRecordListView: View {
    var taskID: String? = nil
    @Environment(DemoSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DemoPage {
            Text("操作留痕使用实际时间。演示操作者是\(ApprovalExecutionMath.operatorName)。")
                .font(DemoTheme.Typography.caption)
                .foregroundStyle(DemoTheme.ColorToken.secondaryText)
            if taskID == nil {
                let rejected = session.rejectedTasks()
                if rejected.isEmpty {
                    Text("当前没有被拒绝的任务。")
                        .font(DemoTheme.Typography.body)
                } else {
                    Text("被拒绝的任务").font(DemoTheme.Typography.title)
                    ForEach(rejected) { task in
                        DemoCard {
                            Text(task.displayName).font(DemoTheme.Typography.heading)
                            DemoValueRow(title: "状态", value: task.approvalStatus.rawValue)
                            NavigationLink("查看原配置") { ApprovalDetailView(taskID: task.id) }
                                .buttonStyle(DemoSecondaryButtonStyle())
                        }
                    }
                }
            }
            let records = session.records(for: taskID)
            if records.isEmpty {
                DemoEmptyState(title: "没有处理记录", message: "调整、确认、执行或重试之后会出现在这里。")
            } else {
                Text("记录").font(DemoTheme.Typography.title)
                ForEach(records) { record in
                    NavigationLink {
                        ApprovalRecordDetailView(recordID: record.id)
                    } label: {
                        DemoCard {
                            Text(record.kind.rawValue).font(DemoTheme.Typography.heading)
                            DemoValueRow(title: "时间", value: DemoFormat.dateTime(record.at))
                            DemoValueRow(title: "任务", value: session.task(id: record.taskID)?.displayName ?? record.taskID)
                            Text(record.note)
                                .font(DemoTheme.Typography.caption)
                                .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("返回") { dismiss() }.buttonStyle(DemoSecondaryButtonStyle())
        }
        .navigationTitle(taskID == nil ? "处理记录" : "任务记录")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ApprovalRecordDetailView: View {
    let recordID: String
    @Environment(DemoSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DemoPage {
            if let record = session.records(for: nil).first(where: { $0.id == recordID }) {
                DemoCard {
                    DemoValueRow(title: "操作", value: record.kind.rawValue)
                    DemoValueRow(title: "时间", value: DemoFormat.dateTime(record.at))
                    DemoValueRow(title: "操作者", value: record.operatorName)
                    DemoValueRow(title: "操作前", value: record.beforeSummary)
                    DemoValueRow(title: "操作后", value: record.afterSummary)
                    Text(record.note).font(DemoTheme.Typography.body)
                }
                NavigationLink("查看任务") { ApprovalDetailView(taskID: record.taskID) }
                    .buttonStyle(DemoSecondaryButtonStyle())
            } else {
                DemoEmptyState(title: "记录不存在", message: "重置演示后，旧页面上的记录会消失。")
            }
            Button("返回") { dismiss() }.buttonStyle(DemoSecondaryButtonStyle())
        }
        .navigationTitle("记录详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}
