import SwiftUI

private struct PlanSessionKey: EnvironmentKey {
    static let defaultValue: (any PlanSessionAccess)? = nil
}

extension EnvironmentValues {
    var planSession: (any PlanSessionAccess)? {
        get { self[PlanSessionKey.self] }
        set { self[PlanSessionKey.self] = newValue }
    }
}

/// 临时只读投影，不存业务数组；接线后直接读取 A 的 Observable 会话。
@MainActor
struct PlanContext {
    let store: MockDataStore
    let session: (any PlanSessionAccess)?
    var plans: [MarketingPlan] { session?.plans ?? store.plans }
    var audiences: [Audience] { session?.audiences ?? store.audiences }
    var metadata: [String: PlanMetadata] { session?.planMetadata ?? store.planMetadata }
    var versions: [PlanVersionSnapshot] { session?.planVersions ?? store.planVersions }
    var resources: [StoreResource] { session?.storeResources ?? store.storeResources }
    var templates: [PlanTemplate] { session?.planTemplates ?? store.planTemplates }
    var suggestions: [PlanSuggestion] { session?.planSuggestions ?? store.planSuggestions }
    var rules: [TouchRule] { session?.touchRules ?? store.touchRules }
    var generations: [PlanRuleGeneration] { session?.ruleGenerations ?? [] }
    var ranges: [PlanRuleRange] { session?.planRuleRanges ?? store.planRuleRanges }
    var referenceDate: Date { session?.planReferenceDate ?? MockDataStore.planReferenceDate }
    var recommendedPercentage: Int { session?.planRecommendedPrimaryPercentage ?? MockDataStore.planRecommendedPrimaryPercentage }
    func plan(id: String) -> MarketingPlan? { plans.first { $0.id == id } }
    func content(for plan: MarketingPlan) -> PlanContent {
        PlanContent(plan: plan, resourceID: metadata[plan.id]?.resourceID)
    }
    func preview(rule: TouchRule) throws -> PlanRulePreview {
        try PlanValidation.preview(rule: rule, plans: plans, metadata: metadata,
                                   resources: resources, audiences: audiences, ranges: ranges, referenceDate: referenceDate)
    }
}

struct PlanConnectionNotice: View {
    var body: some View {
        DemoEmptyState(title: "当前可浏览与编辑草稿", message: "保存与任务生成尚未接通，草稿不会写入。")
    }
}

struct PlanErrorsView: View {
    let messages: [String]
    var body: some View {
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: DemoTheme.Spacing.small) {
                Label("请核对以下内容", systemImage: "exclamationmark.circle").font(DemoTheme.Typography.heading)
                ForEach(messages, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
            }.accessibilityElement(children: .combine)
        }
    }
}

enum PlanPresentation {
    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = DemoFormat.locale
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }

    static func matchesNumber(_ plan: MarketingPlan, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let numeric = trimmed.hasPrefix("方案") ? String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
        guard !numeric.isEmpty, numeric.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(numeric) else { return false }
        return number == plan.number
    }
}
