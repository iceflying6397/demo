import SwiftUI

struct PlanEditView: View {
    let store: MockDataStore
    // 与草稿同时冻结打开时的基础版本，父视图刷新不能偷偷升级保存基线。
    @State private var original: PlanContent
    @State private var existingPlan: MarketingPlan?
    @Environment(\.planSession) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlanContent
    @State private var draftID: String
    @State private var source: CreationSource = .manual
    @State private var showDiscard = false
    @State private var errors: [String] = []
    @State private var submitted = false
    @State private var savedPlan: MarketingPlan?

    init(store: MockDataStore, plan: MarketingPlan?, resourceID: String?) {
        self.store = store
        _existingPlan = State(initialValue: plan)
        let content = plan.map { PlanContent(plan: $0, resourceID: resourceID) } ?? PlanContent()
        _original = State(initialValue: content)
        _draft = State(initialValue: content)
        _draftID = State(initialValue: plan?.id ?? "plan-\(UUID().uuidString)")
    }

    private var context: PlanContext { .init(store: store, session: session) }
    private var dirty: Bool { draft != original || (existingPlan == nil && source != .manual) }
    private var fieldErrors: [String] {
        PlanValidation.errors(content: draft, resources: context.resources, audiences: context.audiences, on: context.referenceDate)
    }

    var body: some View {
        Form {
            if submitted, let savedPlan {
                Section("保存结果") {
                    Text("\(savedPlan.displayName) · V\(savedPlan.version)")
                    Text("内容已提交到共享会话。无实质变化时保留当前版本。")
                    NavigationLink("查看方案详情") { PlanDetailView(plan: savedPlan, store: store) }
                    Button("返回") { dismiss() }
                }
            } else {
                if session == nil { Section { PlanConnectionNotice() } }
                if existingPlan == nil { templateSection }
                Section("目的与适用客户") {
                    Picker("主要目的", selection: $draft.purpose) {
                        ForEach(PlanPurpose.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("适用客户", selection: $draft.customerStage) {
                        ForEach(CustomerStage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("完整话术") {
                    TextField("请输入准备发送的完整内容", text: $draft.message, axis: .vertical)
                        .lineLimit(6...20).accessibilityIdentifier("plan.editor.message")
                    if draft.normalized.message.isEmpty { Text("话术不能为空。").font(.footnote) }
                }
                Section("搭配资源") {
                    Text(draft.resourceID.map { id in context.resources.first { $0.id == id }?.name ?? "资源不可用" } ?? "纯话术 · 无搭配资源")
                    NavigationLink("选择／替换店铺资源") {
                        PlanResourcePickerView(resources: context.resources, referenceDate: context.referenceDate, selectedID: draft.resourceID) {
                            draft.resourceID = $0
                        }
                    }
                    if draft.resourceID != nil { Button("移除资源") { draft.resourceID = nil } }
                    Text("演示约定：零或一个主资源，不访问店铺。").font(.footnote)
                }
                Section("关联人群 · 可多选") {
                    ForEach(context.audiences) { audience in
                        Toggle(audience.displayName, isOn: Binding(get: { draft.audienceIDs.contains(audience.id) }, set: { selected in
                            draft.audienceIDs.removeAll { $0 == audience.id }
                            if selected { draft.audienceIDs.append(audience.id) }
                        }))
                    }
                    ForEach(draft.audienceIDs.filter { id in !context.audiences.contains { $0.id == id } }, id: \.self) { id in
                        Button("移除不可用人群（\(id)）") { draft.audienceIDs.removeAll { $0 == id } }
                    }
                }
                Section {
                    PlanErrorsView(messages: errors)
                    if session == nil {
                        Button("校验草稿") { errors = fieldErrors.isEmpty ? ["草稿校验通过；尚未保存。"] : fieldErrors }
                            .buttonStyle(DemoSecondaryButtonStyle())
                    } else {
                        Button(existingPlan == nil ? "保存新方案" : "保存修改", action: save)
                            .buttonStyle(DemoPrimaryButtonStyle()).accessibilityIdentifier("plan.editor.save")
                    }
                    Button("取消", action: cancel).buttonStyle(DemoSecondaryButtonStyle())
                }
            }
        }
        .navigationTitle(existingPlan == nil ? "新建方案" : "编辑方案")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回", action: cancel) } }
        .confirmationDialog("放弃未保存的修改？", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("放弃修改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) { }
        }
    }

    private var templateSection: some View {
        Section("创建方式") {
            Picker("来源", selection: $source) {
                Text("手动创建").tag(CreationSource.manual)
                Text("模拟 AI 模板").tag(CreationSource.ai)
            }
            if source == .ai {
                ForEach(context.templates) { template in
                    Button("填入\(template.title)") { draft = template.content }
                }
                Text("模板只填入草稿，核对后保存；没有调用 AI 服务。").font(.footnote)
            }
        }
    }

    private func cancel() {
        if dirty && !submitted { showDiscard = true } else { dismiss() }
    }

    private func save() {
        guard !submitted, let session else { return }
        errors = fieldErrors
        guard errors.isEmpty else { return }
        do {
            savedPlan = try session.savePlan(.init(id: draftID, baseVersion: existingPlan?.version, content: draft,
                                                   creationSource: existingPlan?.source ?? source))
            submitted = true
        } catch { errors = [error.localizedDescription] }
    }
}
