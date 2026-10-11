import SwiftUI

struct AnalyticsFilterView: View {
    let store: MockDataStore
    let apply: (AnalyticsSelection) -> Void
    @State var draft: AnalyticsSelection
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    private var planChoices: [(id: String, name: String)] {
        var choices = store.plans.map { (id: $0.id, name: $0.displayName) }
        for (id, name) in [("plan-01", "方案 01"), ("plan-02", "方案 02")] where !choices.contains(where: { $0.id == id }) {
            choices.append((id, name + " · 历史编号"))
        }
        // A historical filter reference with no result, used to validate the three-choice limit and empty state.
        if !choices.contains(where: { $0.id == "plan-03" }) { choices.append(("plan-03", "方案 03 · 暂无样本")) }
        return choices
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("时间 · 两方案共用") {
                    Picker("时间范围", selection: $draft.period) {
                        ForEach(AnalyticsPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Text(draft.period.range.label).font(.footnote)
                    Text("固定参考日2026/10/11 · Asia/Shanghai").font(.footnote).foregroundStyle(.secondary)
                }
                Section("人群") {
                    Picker("选择人群", selection: $draft.audienceID) {
                        Text("全部人群 · 预去重摘要").tag(String?.none)
                        ForEach(store.audiences) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                }
                Section("方案 · 最多两套") {
                    Button("不指定方案（当前范围合计）") { draft.planIDs = []; error = nil }
                    ForEach(planChoices, id: \.id) { choice in
                        Button {
                            error = draft.toggle(choice.id) ? nil : "最多选择两套方案，请先移除一套。"
                        } label: {
                            HStack {
                                Text(choice.name)
                                Spacer()
                                if draft.planIDs.contains(choice.id) { Image(systemName: "checkmark") }
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("analytics.filter.\(choice.id)")
                    }
                    if let error { Text(error).foregroundStyle(.secondary).accessibilityIdentifier("analytics.filter.limit") }
                    Text("不指定时显示范围合计；旧记录按发送版本读取。方案03是无结果的边界引用，不创建业务方案。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("清除（恢复默认草稿）") { draft = AnalyticsSelection(); error = nil }
                    Button("应用筛选") {
                        guard draft.query.valid else { error = "最多选择两套不同方案。"; return }
                        apply(draft); dismiss()
                    }
                    .accessibilityIdentifier("analytics.filter.apply")
                }
            }
            .navigationTitle("数据筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.accessibilityIdentifier("analytics.filter.cancel") } }
        }
    }
}
