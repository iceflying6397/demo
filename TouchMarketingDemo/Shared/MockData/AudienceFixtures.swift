import Foundation

extension MockDataStore {
    static let audienceFields: [AudienceField] = [
        .init(id: "field-days", name: "距上次购买天数", type: .number, explanation: "距最近支付日的天数", options: [], evidence: "订单支付日期", isEnabled: true, version: 1, isBuiltIn: true),
        .init(id: "field-count", name: "观察期购买次数", type: .number, explanation: "90日有效支付次数", options: [], evidence: "支付订单", isEnabled: true, version: 1, isBuiltIn: true),
        .init(id: "field-amount", name: "观察期实付金额（元）", type: .number, explanation: "90日固定观察期内实付金额", options: [], evidence: "订单实付金额", isEnabled: true, version: 1, isBuiltIn: true),
        .init(id: "field-category", name: "品类", type: .category, explanation: "购买的商品品类", options: ["品类 A", "品类 B", "其他"], evidence: "商品品类", isEnabled: true, version: 1, isBuiltIn: true),
        .init(id: "field-date", name: "最近购买日期", type: .date, explanation: "最近支付日（上海时区）", options: [], evidence: "订单支付日期", isEnabled: true, version: 1, isBuiltIn: true),
        .init(id: "field-repeat", name: "有复购记录", type: .boolean, explanation: "观察期内是否再次购买", options: [], evidence: "订单记录", isEnabled: true, version: 1, isBuiltIn: true)
    ]

    static func audienceRules(number: Int) -> AudienceRules {
        let field = audienceFields[0]
        return AudienceRules(relation: .and, conditions: [
            .init(id: "condition-\(number)-days", field: field, operation: .atMost, value: .number(number == 1 ? 90 : 30))
        ], instruction: "按90日固定样本观察购买行为，画像仅为本地模拟。")
    }

    static let audienceSuggestions: [DemoSuggestion] = {
        var rules = audienceRules(number: 1)
        rules.conditions.append(.init(id: "suggestion-condition-count", field: audienceFields[1], operation: .atLeast, value: .number(2)))
        return [
            .init(id: "suggestion-audience-valid", targetKind: .audience, targetID: "audience-01", baseVersion: 1,
                  summary: "增加观察期购买次数不少于2次", evidence: "2026/10/05—10/11，历史批次 task-history-01 固定样本；不是规则效果预测。", expectedImpact: "预计缩小范围以便继续验证；覆盖与画像需重新模拟识别，未执行真实筛选。", proposedRules: rules, status: .pending),
            .init(id: "suggestion-audience-expired", targetKind: .audience, targetID: "audience-02", baseVersion: 0,
                  summary: "早期规则优化（旧版本示例）", evidence: "旧版演示草案，基础版本已过期。", expectedImpact: "需重新核对最新版，不允许直接覆盖。", proposedRules: rules, status: .expired)
        ]
    }()

    /// Explicit pre-deduplicated fixture; only valid for the unchanged initial range.
    static let audienceUnionCoverage = 11_000 // 8,420 + 3,160 - overlap 580
}
