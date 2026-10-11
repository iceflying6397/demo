import SwiftUI

struct AudienceFieldListView: View {
    let session: DemoSession
    @State private var creating = false
    @State private var editing: AudienceField?
    @State private var error: String?
    var body: some View {
        DemoPage {
            Text("字段定义保存在共享字典；历史规则保留当时版本。停用代替删除，内置字段语义不可修改。")
            Button("新增自定义字段") { creating = true }.buttonStyle(DemoPrimaryButtonStyle())
            ForEach(session.fields) { field in
                DemoCard {
                    Text(field.name).font(DemoTheme.Typography.heading)
                    DemoValueRow(title: "类型／版本", value: "\(field.type.rawValue) · V\(field.version)")
                    DemoValueRow(title: "状态", value: field.isEnabled ? "启用" : "停用")
                    Text(field.explanation)
                    if field.type == .category { Text("属性值：\(field.options.joined(separator: "、"))") }
                    Text("识别依据：\(field.evidence)").font(DemoTheme.Typography.caption)
                    if !field.isBuiltIn {
                        Button("编辑字段") { editing = field }.buttonStyle(DemoSecondaryButtonStyle())
                    }
                    Button(field.isEnabled ? "停用字段" : "启用字段") {
                        do { var copy = field; copy.isEnabled.toggle(); try session.saveField(copy) }
                        catch { self.error = error.localizedDescription }
                    }.buttonStyle(DemoSecondaryButtonStyle())
                }
            }
        }
        .navigationTitle("字段管理").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) { NavigationStack { AudienceFieldEditView(session: session, field: nil) } }
        .sheet(item: $editing) { field in NavigationStack { AudienceFieldEditView(session: session, field: field) } }
        .alert("操作未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了") { error = nil } } message: { Text(error ?? "") }
    }
}

private struct AudienceFieldEditView: View {
    let session: DemoSession
    private let original: AudienceField
    @State private var draft: AudienceField
    @State private var discard = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(session: DemoSession, field: AudienceField?) {
        self.session = session
        let initial = field ?? AudienceField(id: UUID().uuidString, name: "", type: .category, explanation: "", options: [""], evidence: "", isEnabled: true, version: 0, isBuiltIn: false)
        original = initial; _draft = State(initialValue: initial)
    }
    var body: some View {
        Form {
            Section("字段定义") {
                TextField("字段名称", text: $draft.name)
                Picker("类型", selection: $draft.type) { ForEach(AudienceFieldType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                TextField("说明", text: $draft.explanation, axis: .vertical)
                TextField("识别依据", text: $draft.evidence, axis: .vertical)
                Toggle("启用", isOn: $draft.isEnabled)
            }
            if draft.type == .category {
                Section("分类属性值") {
                    ForEach(draft.options.indices, id: \.self) { index in
                        HStack {
                            TextField("属性值", text: Binding(get: { draft.options.indices.contains(index) ? draft.options[index] : "" }, set: { if draft.options.indices.contains(index) { draft.options[index] = $0 } }))
                            Button { draft.options.remove(at: index) } label: { Image(systemName: "minus.circle").accessibilityLabel("删除属性值 \(index + 1)") }.buttonStyle(.borderless)
                        }
                    }
                    Button("添加属性值") { draft.options.append("") }
                }
            }
            if let error { Section("请修正后保存") { Text(error) } }
            Section {
                Button("保存字段") {
                    do { try session.saveField(draft); dismiss() } catch { self.error = error.localizedDescription }
                }
                Text("保存会更新字典定义，已保存的人群版本不会被改写。")
            }
        }
        .navigationTitle(original.version == 0 ? "新增字段" : "编辑字段").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { if draft != original { discard = true } else { dismiss() } } } }
        .interactiveDismissDisabled(draft != original)
        .confirmationDialog("放弃未保存的字段？", isPresented: $discard, titleVisibility: .visible) {
            Button("放弃修改", role: .destructive) { dismiss() }
            Button("保留编辑", role: .cancel) { }
        }
    }
}
