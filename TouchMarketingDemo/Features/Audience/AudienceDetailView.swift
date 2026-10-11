import SwiftUI

struct AudienceDetailView: View {
    let audienceID: String
    let session: DemoSession
    @State private var editing = false
    @State private var error: String?
    var body: some View {
        DemoPage {
            if let snapshot = session.audience(id: audienceID) {
                DemoCard {
                    DemoValueRow(title: "覆盖人数", value: snapshot.recognition == .ready || snapshot.recognition == .empty ? "\(DemoFormat.count(snapshot.audience.memberCount)) 人" : "待统计")
                    DemoValueRow(title: "来源", value: snapshot.audience.source.rawValue)
                    DemoValueRow(title: "版本", value: "V\(snapshot.audience.version)")
                    DemoValueRow(title: "更新时间", value: DemoFormat.timestamp(snapshot.metadata.updatedAt))
                }
                DemoCard {
                    Text("六项画像 · 本地模拟").font(DemoTheme.Typography.heading)
                    AudienceProfileView(snapshot: snapshot)
                    NavigationLink("评分说明") { AudienceScoreExplanationView(metadata: snapshot.metadata) }
                }
                DemoCard {
                    Text("人群规则").font(DemoTheme.Typography.heading)
                    AudienceRulesView(rules: snapshot.rules)
                }
                if snapshot.recognition == .recognizing {
                    DemoCard {
                        Text("模拟识别中").font(DemoTheme.Typography.heading)
                        Text("预计覆盖待统计。规则保存未执行真实筛选；选择确定的场景完成本版本识别，不新增版本。完成场景固定借用人群01画像及8,420覆盖，与规则无计算关系。")
                        ForEach([AudienceRecognition.ready, .insufficient, .empty], id: \.self) { scenario in
                            Button("模拟结果：\(scenario.rawValue)") {
                                do { try session.completeRecognition(id: audienceID, version: snapshot.audience.version, scenario: scenario) }
                                catch { self.error = error.localizedDescription }
                            }.buttonStyle(DemoSecondaryButtonStyle())
                        }
                    }
                }
                NavigationLink("人群 AI 建议") { AudienceSuggestionListView(session: session, audienceID: audienceID) }
                    .buttonStyle(DemoSecondaryButtonStyle())
                DemoCard {
                    Text("关联方案").font(DemoTheme.Typography.heading)
                    let plans = session.plans.filter { $0.audienceIDs.contains(audienceID) }
                    if plans.isEmpty { Text("暂无关联方案") }
                    ForEach(plans) { plan in
                        Text("\(plan.displayName) · \(plan.purpose.rawValue) · \(plan.customerStage.rawValue)")
                    }
                    Text("请切换到底部「方案」Tab，按编号查看方案详情。")
                        .font(DemoTheme.Typography.caption)
                }
                NavigationLink("历史版本") { AudienceHistoryView(session: session, audienceID: audienceID) }
                    .buttonStyle(DemoSecondaryButtonStyle())
                Button("编辑人群规则") { editing = true }.buttonStyle(DemoPrimaryButtonStyle())
                    .accessibilityIdentifier("audience.edit")
            } else {
                DemoEmptyState(title: "人群不可用", message: "该对象已重置或不存在，请返回首页。")
            }
        }
        .navigationTitle(session.audience(id: audienceID)?.audience.displayName ?? "人群详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { NavigationStack { AudienceEditView(session: session, audienceID: audienceID) } }
        .alert("操作未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了") { error = nil } } message: { Text(error ?? "") }
    }
}
