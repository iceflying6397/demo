import SwiftUI

struct AudienceHomeView: View {
    @State private var session: DemoSession
    @State private var source = "全部"
    @State private var expanded: Set<String> = []
    @State private var creating = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(store: MockDataStore, session: DemoSession? = nil) {
        _session = State(initialValue: session ?? DemoSession(store: store))
    }
    private var filtered: [Audience] { session.audiences.filter { source == "全部" || $0.source.rawValue == source } }
    var body: some View {
        DemoPage {
            DemoIntro(description: "了解客户宏观画像，管理规则与版本。")
            if dynamicTypeSize.isAccessibilitySize {
                sourcePicker.pickerStyle(.menu)
            } else { sourcePicker.pickerStyle(.segmented) }
            if source != "全部" {
                Button("清除筛选") { source = "全部" }.buttonStyle(DemoSecondaryButtonStyle())
            }
            DemoCard {
                Text("\(filtered.count) 个人群").font(DemoTheme.Typography.title)
                DemoValueRow(title: "范围去重覆盖", value: session.coverage(for: filtered).map { "\(DemoFormat.count($0)) 人" } ?? "待统计")
                Text("客户可交叉归属，发送按优先级去重；人数不能直接相加。初始联合覆盖为固定去重样本。")
                    .font(DemoTheme.Typography.caption).foregroundStyle(DemoTheme.ColorToken.secondaryText)
            }
            Button("新建人群") { creating = true }.buttonStyle(DemoPrimaryButtonStyle())
                .accessibilityIdentifier("audience.create")
            NavigationLink("人群 AI 建议") { AudienceSuggestionListView(session: session) }
                .buttonStyle(DemoSecondaryButtonStyle())
            NavigationLink("字段管理") { AudienceFieldListView(session: session) }
                .buttonStyle(DemoSecondaryButtonStyle())
            if filtered.isEmpty {
                DemoEmptyState(title: session.audiences.isEmpty ? "暂无人群" : "无筛选结果", message: session.audiences.isEmpty ? "新建规则，开始模拟识别。" : "清除来源筛选后查看其他人群。")

            }
            ForEach(filtered) { audience in
                if let snapshot = session.audience(id: audience.id) {
                    DemoCard {
                        Text(audience.displayName).font(DemoTheme.Typography.heading)
                        DemoValueRow(title: "覆盖人数", value: snapshot.recognition == .ready || snapshot.recognition == .empty ? "\(DemoFormat.count(audience.memberCount)) 人" : "待统计")
                        AudienceProfileView(snapshot: snapshot, coreOnly: !expanded.contains(audience.id))
                        Button(expanded.contains(audience.id) ? "收起完整画像" : "展开完整画像") {
                            if expanded.contains(audience.id) { expanded.remove(audience.id) } else { expanded.insert(audience.id) }
                        }.buttonStyle(DemoSecondaryButtonStyle()).accessibilityIdentifier("audience.expand.\(audience.id)")
                        NavigationLink("查看详情") { AudienceDetailView(audienceID: audience.id, session: session) }
                            .buttonStyle(DemoPrimaryButtonStyle()).accessibilityIdentifier("audience.\(audience.id)")
                    }
                }
            }
        }
        .navigationTitle("人群")
        .sheet(isPresented: $creating) { NavigationStack { AudienceEditView(session: session, audienceID: nil) } }
    }
    private var sourcePicker: some View {
        Picker("创建来源", selection: $source) {
            Text("全部").tag("全部")
            ForEach(CreationSource.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
        }
    }
}

#Preview { NavigationStack { AudienceHomeView(store: .demo) } }
