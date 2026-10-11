import SwiftUI

struct AudienceEditView: View {
    let session: DemoSession
    let audienceID: String?
    private let baseVersion: Int?
    private let initialConditions: [AudienceConditionDraft]
    private let initialRelation: AudienceRules.Relation
    private let initialInstruction: String
    @State private var conditions: [AudienceConditionDraft]
    @State private var relation: AudienceRules.Relation
    @State private var instruction: String
    @State private var discard = false
    @State private var error: String?
    @State private var saved: AudienceSnapshot?
    @State private var unchanged = false
    @Environment(\.dismiss) private var dismiss

    init(session: DemoSession, audienceID: String?) {
        self.session = session; self.audienceID = audienceID
        let snapshot = audienceID.flatMap { session.audience(id: $0) }
        baseVersion = snapshot?.audience.version
        let rows = snapshot?.rules.conditions.map(AudienceConditionDraft.init(condition:)) ?? session.fields.filter(\.isEnabled).prefix(1).map { AudienceConditionDraft(field: $0) }
        initialConditions = rows; initialRelation = snapshot?.rules.relation ?? .and; initialInstruction = snapshot?.rules.instruction ?? ""
        _conditions = State(initialValue: rows)
        _relation = State(initialValue: initialRelation)
        _instruction = State(initialValue: initialInstruction)
    }
    private var changed: Bool { conditions != initialConditions || relation != initialRelation || instruction != initialInstruction }
    var body: some View {
        Group {
            if let saved {
                DemoPage {
                    DemoCard {
                        Text(unchanged ? "没有修改" : "规则已保存 · V\(saved.audience.version)").font(DemoTheme.Typography.title)
                        Text(unchanged ? "未生成额外版本。" : "\(saved.audience.displayName)进入模拟识别，预计覆盖待统计；没有运行真实筛选。")
                    }
                    NavigationLink("查看人群与识别状态") { AudienceDetailView(audienceID: saved.audience.id, session: session) }
                        .buttonStyle(DemoPrimaryButtonStyle())
                    Button("完成并返回") { dismiss() }.buttonStyle(DemoSecondaryButtonStyle())
                }
            } else {
                Form {
                    Section {
                        Text(audienceID.flatMap { session.audience(id: $0)?.audience.displayName } ?? "保存后分配稳定编号")
                        if let baseVersion { Text("正在编辑 V\(baseVersion)，评分由模拟识别产生，不能手填。") }
                    }
                    Section("条件关系") {
                        Picker("满足方式", selection: $relation) { ForEach(AudienceRules.Relation.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    }
                    ForEach($conditions) { $condition in
                        Section("条件") {
                            AudienceRuleRow(draft: $condition, fields: session.fields)
                            Button("移除此条件", role: .destructive) { conditions.removeAll { $0.id == condition.id } }
                        }
                    }
                    Section {
                        Button("添加条件") {
                            if let field = session.fields.first(where: { $0.isEnabled && !conditions.map(\.field.id).contains($0.id) }) { conditions.append(.init(field: field)) }
                        }.disabled(!session.fields.contains(where: { $0.isEnabled && !conditions.map(\.field.id).contains($0.id) }))
                        Text("同一字段只能有一条条件，数值范围请使用「介于」。").font(DemoTheme.Typography.caption)
                        NavigationLink("管理／新增自定义字段") { AudienceFieldListView(session: session) }
                    }
                    Section("给模拟 AI 的规则说明") {
                        TextField("说明观察依据", text: $instruction, axis: .vertical).lineLimit(3...8)
                        Text("所有结果均来自固定样本，规则不执行真实客户筛选。").font(DemoTheme.Typography.caption)
                    }
                    if let error { Section("请修正后保存") { Text(error).accessibilityIdentifier("audience.validation") } }
                    Section { Button("保存规则", action: save).accessibilityIdentifier("audience.save") }
                }
            }
        }
        .navigationTitle(audienceID == nil ? "新建人群" : "编辑人群")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(saved == nil ? "取消" : "关闭") { if saved == nil && changed { discard = true } else { dismiss() } } }
        }
        .interactiveDismissDisabled(saved == nil && changed)
        .confirmationDialog("放弃未保存的规则？", isPresented: $discard, titleVisibility: .visible) {
            Button("放弃修改", role: .destructive) { dismiss() }
            Button("保留编辑", role: .cancel) { }
        }
    }
    private func save() {
        do {
            let rules = AudienceRules(relation: relation, conditions: try conditions.map { try $0.condition() }, instruction: instruction)
            let result = try session.saveAudience(id: audienceID, baseVersion: baseVersion, rules: rules)
            unchanged = baseVersion == result.audience.version
            saved = result; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct AudienceRuleRow: View {
    @Binding var draft: AudienceConditionDraft
    let fields: [AudienceField]
    private var choices: [AudienceField] {
        let current = fields.filter(\.isEnabled)
        // Retain the saved definition for an existing condition, including disabled fields.
        return current.filter { $0.id != draft.field.id } + [draft.field]
    }
    var body: some View {
        Picker("字段", selection: Binding(get: { draft.field.id }, set: { id in
            if let field = fields.first(where: { $0.id == id && $0.isEnabled }) {
                let stableID = draft.id
                draft = AudienceConditionDraft(field: field); draft.id = stableID
            }
        })) {
            ForEach(choices) { field in Text(field.name + (field.isEnabled ? "" : "（已停用）")).tag(field.id) }
        }
        if let latest = fields.first(where: { $0.id == draft.field.id }), latest != draft.field {
            Text("该条件保留字段 V\(draft.field.version)。新定义为 V\(latest.version)。未修改条件可保留旧定义。")
                .font(DemoTheme.Typography.caption)
            if latest.isEnabled { Button("使用最新字段定义") {
                let id = draft.id; draft = AudienceConditionDraft(field: latest); draft.id = id
            } }
        }
        Picker("判断方式", selection: $draft.operation) {
            ForEach(AudienceRuleOperator.allowed(for: draft.field.type), id: \.self) { Text($0.rawValue).tag($0) }
        }
        switch draft.field.type {
        case .number:
            TextField(draft.operation == .between ? "下限" : "数值", text: $draft.text).keyboardType(.decimalPad)
            if draft.operation == .between { TextField("上限", text: $draft.upper).keyboardType(.decimalPad) }
        case .category:
            Picker("属性值", selection: $draft.text) {
                Text("请选择").tag("")
                ForEach(draft.field.options, id: \.self) { Text($0).tag($0) }
            }
        case .date:
            DatePicker("日期（上海）", selection: $draft.date, displayedComponents: .date)
                .environment(\.timeZone, DemoClock.calendar.timeZone)
        case .boolean: Toggle("属性值：是", isOn: $draft.boolean)
        }
        Text(draft.field.explanation).font(DemoTheme.Typography.caption)
    }
}
