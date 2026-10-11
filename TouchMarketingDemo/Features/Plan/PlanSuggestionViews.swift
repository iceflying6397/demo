import SwiftUI

struct PlanSuggestionListView: View {
    let store: MockDataStore
    let planID: String
    @Environment(\.planSession) private var session
    private var suggestions: [PlanSuggestion] {
        PlanContext(store: store, session: session).suggestions.filter { $0.planID == planID }
    }
    var body: some View {
        DemoPage {
            Text("本地模拟建议 · 查看不会修改方案")
            if suggestions.isEmpty { DemoEmptyState(title: "暂无方案建议", message: "当前没有针对这套方案的模拟建议。") }
            ForEach(suggestions) { suggestion in
                NavigationLink { PlanSuggestionDetailView(store: store, suggestionID: suggestion.id) } label: {
                    DemoCard {
                        DemoValueRow(title: "基础版本", value: "V\(suggestion.baseVersion)")
                        DemoValueRow(title: "处理状态", value: suggestion.status.rawValue)
                        Text(suggestion.reason).fixedSize(horizontal: false, vertical: true)
                    }
                }.buttonStyle(.plain)
            }
        }.navigationTitle("方案建议").navigationBarTitleDisplayMode(.inline)
    }
}

struct PlanSuggestionDetailView: View {
    let store: MockDataStore
    let suggestionID: String
    @Environment(\.planSession) private var session
    @State private var confirmAdoption = false
    @State private var errors: [String] = []
    private var context: PlanContext { .init(store: store, session: session) }
    private var suggestion: PlanSuggestion? { context.suggestions.first { $0.id == suggestionID } }

    var body: some View {
        DemoPage {
            if let suggestion, let plan = context.plan(id: suggestion.planID) {
                if suggestion.status == .adopted {
                    adoptionResult(suggestion, plan: plan)
                } else {
                    Text("本地模拟建议 · 采纳需确认")
                    DemoCard {
                        DemoValueRow(title: "目标方案", value: plan.displayName)
                        DemoValueRow(title: "基础／当前版本", value: "V\(suggestion.baseVersion) / V\(plan.version)")
                        DemoValueRow(title: "状态", value: suggestion.status.rawValue)
                        DemoValueRow(title: "参考数据", value: DemoFormat.dateRange(start: suggestion.evidenceStart, end: suggestion.evidenceEnd))
                        Text(suggestion.reason)
                        Text(suggestion.expectedImpact)
                        if let date = suggestion.handledAt { DemoValueRow(title: "处理时间", value: PlanPresentation.timestamp(date)) }
                    }
                    comparison(title: "当前内容", content: context.content(for: plan))
                    comparison(title: "建议内容", content: suggestion.proposed)
                    PlanErrorsView(messages: adoptionErrors(suggestion, plan: plan))
                    PlanErrorsView(messages: errors)
                    if session == nil { PlanConnectionNotice() } else {
                        Button("确认采纳…") { confirmAdoption = true }
                            .buttonStyle(DemoPrimaryButtonStyle())
                            .disabled(!adoptionErrors(suggestion, plan: plan).isEmpty)
                        Button("暂不采纳") {
                            do { try session?.deferPlanSuggestion(id: suggestion.id) }
                            catch { errors = [error.localizedDescription] }
                        }.buttonStyle(DemoSecondaryButtonStyle()).disabled(suggestion.status == .deferred)
                    }
                }
            } else { DemoEmptyState(title: "建议不可用", message: "请返回列表查看当前记录。") }
        }
        .navigationTitle("建议详情").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("采纳后生成新版本，旧发送快照保持原内容。", isPresented: $confirmAdoption, titleVisibility: .visible) {
            Button("采纳并生成新版本") {
                do { _ = try session?.adoptPlanSuggestion(id: suggestionID) }
                catch { errors = [error.localizedDescription] }
            }
            Button("取消", role: .cancel) { }
        }
    }

    private func comparison(title: String, content: PlanContent) -> some View {
        DemoCard {
            Text(title).font(DemoTheme.Typography.heading)
            DemoValueRow(title: "目的", value: content.purpose.rawValue)
            DemoValueRow(title: "适用客户", value: content.customerStage.rawValue)
            Text(content.message).fixedSize(horizontal: false, vertical: true)
            DemoValueRow(title: "资源", value: content.resourceID.map { id in context.resources.first { $0.id == id }?.name ?? "资源不可用" } ?? "无搭配资源")
            DemoValueRow(title: "关联人群", value: content.audienceIDs.isEmpty ? "未关联" : content.audienceIDs.map { id in context.audiences.first { $0.id == id }?.displayName ?? "人群不可用（\(id)）" }.joined(separator: "、"))
        }
    }

    private func adoptionErrors(_ suggestion: PlanSuggestion, plan: MarketingPlan) -> [String] {
        var result = PlanValidation.errors(content: suggestion.proposed, resources: context.resources,
                                           audiences: context.audiences, on: context.referenceDate)
        if suggestion.baseVersion != plan.version { result.append("基础版本已过期，不能覆盖最新编辑。") }
        return result
    }

    private func adoptionResult(_ suggestion: PlanSuggestion, plan: MarketingPlan) -> some View {
        DemoCard {
            Text("建议已采纳").font(DemoTheme.Typography.title)
            DemoValueRow(title: "方案", value: plan.displayName)
            if let version = suggestion.resultingVersion {
                DemoValueRow(title: "采纳生成版本", value: "V\(version)")
                if let snapshot = context.versions.first(where: { $0.plan.id == plan.id && $0.plan.version == version }) {
                    Text(snapshot.summary)
                    NavigationLink("查看采纳版本") { PlanVersionDetailView(snapshot: snapshot) }
                }
            }
            NavigationLink("返回方案详情") { PlanDetailView(plan: plan, store: store) }
        }
    }
}
