import SwiftUI

struct AudienceSuggestionListView: View {
    let session: DemoSession
    var audienceID: String? = nil
    private var items: [DemoSuggestion] {
        session.suggestions.filter { $0.targetKind == .audience && (audienceID == nil || $0.targetID == audienceID) }
    }
    var body: some View {
        DemoPage {
            Text("本地模拟建议；确认采纳后才更新规则并生成版本。")
            if items.isEmpty { DemoEmptyState(title: "暂无人群建议", message: "当前人群没有固定建议样本。") }
            ForEach(items) { suggestion in
                NavigationLink {
                    AudienceSuggestionDetailView(session: session, suggestionID: suggestion.id)
                } label: {
                    DemoCard {
                        Text(session.audience(id: suggestion.targetID)?.audience.displayName ?? "人群不可用").font(DemoTheme.Typography.heading)
                        Text(suggestion.summary)
                        DemoValueRow(title: "状态／基础版本", value: "\(suggestion.status.rawValue) · V\(suggestion.baseVersion)")
                        if session.audience(id: suggestion.targetID)?.audience.version != suggestion.baseVersion {
                            Text("建议基于旧版本，不能直接采纳")
                        }
                        Text("查看依据与差异 ›")
                    }
                }.buttonStyle(.plain)
            }
        }.navigationTitle("人群 AI 建议").navigationBarTitleDisplayMode(.inline)
    }
}

private struct AudienceSuggestionDetailView: View {
    let session: DemoSession
    let suggestionID: String
    @State private var confirm = false
    @State private var error: String?
    var body: some View {
        DemoPage {
            if let suggestion = session.suggestions.first(where: { $0.id == suggestionID }) {
                DemoCard {
                    Text("本地模拟建议").font(DemoTheme.Typography.heading)
                    Text(session.audience(id: suggestion.targetID)?.audience.displayName ?? "人群不可用")
                    DemoValueRow(title: "基础版本", value: "V\(suggestion.baseVersion)")
                    DemoValueRow(title: "当前版本", value: session.audience(id: suggestion.targetID).map { "V\($0.audience.version)" } ?? "不可用")
                    DemoValueRow(title: "状态", value: suggestion.status.rawValue)
                    Text(suggestion.summary)
                }
                if suggestion.status == .adopted, let version = suggestion.generatedVersion {
                    DemoCard {
                        Text("已采纳 · 生成 V\(version)").font(DemoTheme.Typography.title)
                        if let date = suggestion.processedAt { Text(DemoFormat.timestamp(date)) }
                        Text("采纳记录已保存，不可重复采纳。")
                        NavigationLink("查看人群最新版") { AudienceDetailView(audienceID: suggestion.targetID, session: session) }
                        NavigationLink("查看采纳版本记录") { AudienceHistoryView(session: session, audienceID: suggestion.targetID) }
                    }
                }
                DemoCard {
                    Text("基础规则快照").font(DemoTheme.Typography.heading)
                    if let snapshot = session.audienceVersion(id: suggestion.targetID, version: suggestion.baseVersion) {
                        AudienceRulesView(rules: snapshot.rules)
                    } else { Text("旧版本快照不可用，不以最新版冒充。") }
                    Text("建议规则").font(DemoTheme.Typography.heading)
                    if let proposed = suggestion.proposedRules { AudienceRulesView(rules: proposed) }
                    Text("变化：\(suggestion.summary)")
                }
                DemoCard {
                    Text("数据范围与依据").font(DemoTheme.Typography.heading)
                    Text(suggestion.evidence)
                    Text("预计影响：\(suggestion.expectedImpact)")
                }
                if suggestion.status != .adopted {
                    let stale = session.audience(id: suggestion.targetID)?.audience.version != suggestion.baseVersion
                    if stale || suggestion.status == .expired {
                        DemoEmptyState(title: "建议基于旧版本", message: "请重新核对，已阻止直接覆盖最新版。")
                    }
                    Button("采纳并生成新版本") { confirm = true }
                        .buttonStyle(DemoPrimaryButtonStyle()).disabled(stale || suggestion.status == .expired)
                    if suggestion.status == .pending {
                        Button("暂不采纳") {
                            do { try session.deferSuggestion(id: suggestionID) } catch { self.error = error.localizedDescription }
                        }.buttonStyle(DemoSecondaryButtonStyle())
                    }
                }
            } else { DemoEmptyState(title: "建议不可用", message: "请返回建议列表。") }
        }
        .navigationTitle("建议详情").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("确认采纳此模拟建议？", isPresented: $confirm, titleVisibility: .visible) {
            Button("确认采纳") {
                do { try session.adoptSuggestion(id: suggestionID) } catch { self.error = error.localizedDescription }
            }
            Button("取消", role: .cancel) { }
        } message: { Text("保存建议规则，生成新版本并进入模拟识别。旧版本与旧发送记录保留。") }
        .alert("无法采纳", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了") { error = nil } } message: { Text(error ?? "") }
    }
}
