import SwiftUI

struct PlanVersionListView: View {
    let store: MockDataStore
    let planID: String
    @Environment(\.planSession) private var session
    private var snapshots: [PlanVersionSnapshot] {
        PlanContext(store: store, session: session).versions.filter { $0.plan.id == planID }
            .sorted { $0.plan.version > $1.plan.version }
    }
    var body: some View {
        DemoPage {
            Text("历史保留当时的话术、资源和关联人群，查看不会改变当前版本。")
            if snapshots.isEmpty { DemoEmptyState(title: "暂无历史快照", message: "不能用当前内容代替缺失的历史记录。") }
            ForEach(snapshots) { snapshot in
                NavigationLink { PlanVersionDetailView(snapshot: snapshot) } label: {
                    DemoCard {
                        Text("\(snapshot.plan.displayName) · V\(snapshot.plan.version)").font(DemoTheme.Typography.heading)
                        DemoValueRow(title: "更新时间", value: PlanPresentation.timestamp(snapshot.changedAt))
                        DemoValueRow(title: "变更来源", value: snapshot.changeSource.rawValue)
                        Text(snapshot.summary)
                    }
                }.buttonStyle(.plain)
            }
        }.navigationTitle("历史版本").navigationBarTitleDisplayMode(.inline)
    }
}

struct PlanVersionDetailView: View {
    let snapshot: PlanVersionSnapshot
    var body: some View {
        DemoPage {
            DemoCard {
                Text("\(snapshot.plan.displayName) · V\(snapshot.plan.version)").font(DemoTheme.Typography.title)
                DemoValueRow(title: "目的", value: snapshot.plan.purpose.rawValue)
                DemoValueRow(title: "适用客户", value: snapshot.plan.customerStage.rawValue)
                DemoValueRow(title: "创建来源", value: snapshot.plan.source.rawValue)
                DemoValueRow(title: "变更来源", value: snapshot.changeSource.rawValue)
                DemoValueRow(title: "记录时间", value: PlanPresentation.timestamp(snapshot.changedAt))
                Text(snapshot.summary)
            }
            DemoCard {
                Text("当时话术").font(DemoTheme.Typography.heading)
                Text(snapshot.plan.message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            DemoCard {
                Text("当时资源快照").font(DemoTheme.Typography.heading)
                if let resource = snapshot.resource {
                    PlanResourceContent(resource: resource, referenceDate: snapshot.resourceCheckedAt, historical: true)
                } else { Text(snapshot.metadata.resourceID == nil ? "无搭配资源" : "历史资源快照缺失") }
            }
            DemoCard {
                Text("当时关联的人群 ID").font(DemoTheme.Typography.heading)
                if snapshot.plan.audienceIDs.isEmpty { Text("未关联人群") }
                ForEach(snapshot.plan.audienceIDs, id: \.self) { Text(verbatim: $0) }
                Text("历史引用不随最新人群或方案编辑变化。").font(DemoTheme.Typography.caption)
            }
        }.navigationTitle("版本快照").navigationBarTitleDisplayMode(.inline)
    }
}
