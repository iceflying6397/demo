import SwiftUI

struct PlanDetailView: View {
    let plan: MarketingPlan
    let store: MockDataStore
    @Environment(\.planSession) private var session
    @Environment(\.dismiss) private var dismiss
    private var context: PlanContext { .init(store: store, session: session) }

    var body: some View {
        DemoPage {
            if let current = context.plan(id: plan.id) {
                DemoCard {
                    DemoValueRow(title: "目的", value: current.purpose.rawValue)
                    DemoValueRow(title: "适用客户", value: current.customerStage.rawValue)
                    DemoValueRow(title: "版本", value: "V\(current.version)")
                    DemoValueRow(title: "创建来源", value: current.source.rawValue)
                    if let info = context.metadata[current.id] {
                        DemoValueRow(title: "创建时间", value: PlanPresentation.timestamp(info.createdAt))
                        DemoValueRow(title: "更新时间", value: PlanPresentation.timestamp(info.updatedAt))
                    } else { Text("时间记录不可用") }
                }
                DemoCard {
                    Text("完整话术").font(DemoTheme.Typography.heading)
                    Text(current.message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                DemoCard {
                    Text("搭配资源").font(DemoTheme.Typography.heading)
                    if let info = context.metadata[current.id] {
                        if let resourceID = info.resourceID {
                            if let resource = context.resources.first(where: { $0.id == resourceID }) {
                                PlanResourceContent(resource: resource, referenceDate: context.referenceDate)
                            } else { Text("引用资源不可用，请编辑替换。") }
                        } else { Text("纯话术 · 无搭配资源") }
                    } else { Text("资源引用尚未迁移：\(current.resourceSummary)") }
                    NavigationLink("编辑／替换资源") {
                        PlanEditView(store: store, plan: current, resourceID: context.metadata[current.id]?.resourceID)
                    }.buttonStyle(DemoSecondaryButtonStyle())
                }
                DemoCard {
                    Text("关联人群").font(DemoTheme.Typography.heading)
                    if current.audienceIDs.isEmpty { Text("未关联人群") }
                    ForEach(current.audienceIDs, id: \.self) { id in
                        if let audience = context.audiences.first(where: { $0.id == id }) {
                            DemoValueRow(title: audience.displayName, value: "覆盖 \(DemoFormat.count(audience.memberCount)) 人")
                        } else { Text("人群不可用（\(id)）") }
                    }
                    Text("关联仅作内容适用参考，最终发送范围由审批确认。")
                        .font(DemoTheme.Typography.caption).foregroundStyle(DemoTheme.ColorToken.secondaryText)
                }
                DemoCard {
                    let suggestions = context.suggestions.filter { $0.planID == current.id }
                    DemoValueRow(title: "建议采纳", value: "已采纳 \(suggestions.filter { $0.status == .adopted }.count) 条")
                    NavigationLink("查看本地模拟建议（\(suggestions.count)）") { PlanSuggestionListView(store: store, planID: current.id) }
                    NavigationLink("历史版本") { PlanVersionListView(store: store, planID: current.id) }
                }
                NavigationLink("编辑方案") {
                    PlanEditView(store: store, plan: current, resourceID: context.metadata[current.id]?.resourceID)
                }.buttonStyle(DemoPrimaryButtonStyle())
            } else { DemoEmptyState(title: "方案不可用", message: "请返回首页查看当前方案。") }
            Button("返回") { dismiss() }.buttonStyle(DemoSecondaryButtonStyle())
        }
        .navigationTitle(plan.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
