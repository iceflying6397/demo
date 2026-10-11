import SwiftUI

struct PlanRuleEditView: View {
    let store: MockDataStore
    @State private var existing: TouchRule?
    @State private var original: TouchRuleConfiguration
    @Environment(\.planSession) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: TouchRuleConfiguration
    @State private var draftID: String
    @State private var errors: [String] = []
    @State private var showDiscard = false
    @State private var savedRule: TouchRule?

    init(store: MockDataStore, rule: TouchRule?, kind: TouchRuleKind) {
        self.store = store
        _existing = State(initialValue: rule)
        let draft = rule?.configuration ?? TouchRuleConfiguration(kind: kind)
        _original = State(initialValue: draft)
        _configuration = State(initialValue: draft)
        _draftID = State(initialValue: rule?.id ?? "rule-\(UUID().uuidString)")
    }

    private var context: PlanContext { .init(store: store, session: session) }
    private var draftRule: TouchRule {
        .init(id: draftID, number: existing?.number ?? 0, revision: existing?.revision ?? 0,
              configuration: configuration, updatedAt: existing?.updatedAt ?? context.referenceDate)
    }
    private var doublePlan: Binding<Bool> {
        Binding(get: { configuration.secondaryPlanID != nil }, set: { enabled in
            configuration.secondaryPlanID = enabled ? "" : nil
            configuration.primaryPercentage = enabled ? context.recommendedPercentage : 100
        })
    }

    var body: some View {
        Form {
            if let savedRule {
                Section("规则已保存") {
                    Text("\(savedRule.displayName) · 配置 V\(savedRule.revision)")
                    Text("保存未生成任务，也未发送。")
                    NavigationLink("预览并生成模拟待审批") { PlanRulePreviewView(store: store, rule: savedRule, isDraft: false) }
                    Button("返回") { dismiss() }
                }
            } else {
                if session == nil { Section { PlanConnectionNotice() } }
                Section("条件") {
                    Toggle("启用规则", isOn: $configuration.isEnabled)
                    if configuration.kind == .followUp {
                        Picker("回访周期", selection: $configuration.period) {
                            ForEach(FollowUpPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        Text("起算依据：最近一次购买（演示约定）。按日历月计算，不等同于固定 90 天。")
                    } else {
                        Text("生日条件：参考日当天生日。生日来自本地样本假设，不代表企业微信资料必然包含生日。")
                    }
                }
                Section("卡片生成时间 · 上海时区") {
                    Picker("时", selection: $configuration.hour) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d 时", $0)).tag($0) }
                    }
                    Picker("分", selection: $configuration.minute) {
                        ForEach(0..<60, id: \.self) { Text(String(format: "%02d 分", $0)).tag($0) }
                    }
                    Text("仅保存时间配置；通过预览显式模拟到期，不启动后台调度。").font(.footnote)
                }
                Section("方案与分配") {
                    Picker("方案 A", selection: $configuration.primaryPlanID) {
                        Text("请选择").tag("")
                        ForEach(context.plans) { Text("\($0.displayName) · V\($0.version)").tag($0.id) }
                    }
                    Toggle("双方案测试", isOn: doublePlan)
                    if configuration.secondaryPlanID != nil {
                        Picker("方案 B", selection: Binding(get: { configuration.secondaryPlanID ?? "" }, set: { configuration.secondaryPlanID = $0 })) {
                            Text("请选择另一套方案").tag("")
                            ForEach(context.plans) { Text("\($0.displayName) · V\($0.version)").tag($0.id) }
                        }
                        Stepper("A \(configuration.primaryPercentage)% / B \(100 - configuration.primaryPercentage)%", value: $configuration.primaryPercentage, in: 1...99)
                        Button("恢复模拟 AI 推荐 \(context.recommendedPercentage)% / \(100 - context.recommendedPercentage)%") {
                            configuration.primaryPercentage = context.recommendedPercentage
                        }
                    } else { Text("单方案分配 100%") }
                    Text("最多两套不同方案，每位客户只接收其中一套。").font(.footnote)
                }
                Section("范围预览") {
                    Text(configuration.conditionLabel)
                    NavigationLink("预览当前草稿（不生成任务）") { PlanRulePreviewView(store: store, rule: draftRule, isDraft: true) }
                }
                Section {
                    PlanErrorsView(messages: errors)
                    if session == nil {
                        Button("校验规则草稿", action: validate).buttonStyle(DemoSecondaryButtonStyle())
                    } else {
                        Button("保存规则", action: save).buttonStyle(DemoPrimaryButtonStyle())
                    }
                    Button("取消", action: cancel).buttonStyle(DemoSecondaryButtonStyle())
                }
            }
        }
        .navigationTitle(configuration.kind.rawValue).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回", action: cancel) } }
        .confirmationDialog("放弃未保存的规则配置？", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("放弃修改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) { }
        }
    }

    private func cancel() {
        if configuration != original && savedRule == nil { showDiscard = true } else { dismiss() }
    }
    private func validate() {
        do {
            _ = try PlanValidation.allocation(configuration: configuration, plans: context.plans)
            errors = ["规则草稿校验通过；尚未保存。"]
        } catch { errors = [error.localizedDescription] }
    }
    private func save() {
        guard savedRule == nil, let session else { return }
        do {
            _ = try PlanValidation.allocation(configuration: configuration, plans: context.plans)
            savedRule = try session.saveTouchRule(id: draftID, baseRevision: existing?.revision, configuration: configuration)
        } catch { errors = [error.localizedDescription] }
    }
}
