import SwiftUI

struct AudienceHistoryView: View {
    let session: DemoSession
    let audienceID: String
    var body: some View {
        DemoPage {
            Text("历史版本保留当时的规则、字段定义与画像。支持查看，不提供恢复。")
            ForEach(session.history(kind: .audience, id: audienceID)) { record in
                NavigationLink {
                    AudienceHistoryDetailView(record: record)
                } label: {
                    DemoCard {
                        Text("V\(record.version) · \(record.changeSource.rawValue)").font(DemoTheme.Typography.heading)
                        Text(DemoFormat.timestamp(record.createdAt))
                        Text(record.summary).font(DemoTheme.Typography.caption)
                        Text("查看版本快照 ›")
                    }
                }.buttonStyle(.plain)
            }
        }.navigationTitle("历史版本").navigationBarTitleDisplayMode(.inline)
    }
}

private struct AudienceHistoryDetailView: View {
    let record: VersionRecord
    var body: some View {
        DemoPage {
            if case .audience(let snapshot) = record.content {
                DemoCard {
                    Text("\(snapshot.audience.displayName) · V\(record.version)").font(DemoTheme.Typography.title)
                    Text("\(record.changeSource.rawValue) · \(DemoFormat.timestamp(record.createdAt))")
                    Text(record.summary)
                    DemoValueRow(title: "当时覆盖", value: snapshot.recognition == .ready || snapshot.recognition == .empty ? "\(DemoFormat.count(snapshot.audience.memberCount)) 人" : "待统计")
                }
                DemoCard { AudienceRulesView(rules: snapshot.rules) }
                DemoCard { AudienceProfileView(snapshot: snapshot) }
                NavigationLink("当时评分说明") { AudienceScoreExplanationView(metadata: snapshot.metadata) }
                    .buttonStyle(DemoSecondaryButtonStyle())
            } else { DemoEmptyState(title: "快照缺失", message: "此记录没有人群内容，不能以最新数据代替。") }
        }.navigationTitle("V\(record.version) 快照").navigationBarTitleDisplayMode(.inline)
    }
}
