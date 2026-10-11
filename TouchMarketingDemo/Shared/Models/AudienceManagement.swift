import Foundation

enum AudienceFieldType: String, CaseIterable, Hashable {
    case category = "分类", number = "数值", date = "日期", boolean = "布尔"
}

struct AudienceField: Identifiable, Hashable {
    let id: String
    var name: String
    var type: AudienceFieldType
    var explanation: String
    var options: [String]
    var evidence: String
    var isEnabled: Bool
    var version: Int
    let isBuiltIn: Bool
}

enum AudienceRuleOperator: String, CaseIterable, Hashable {
    case equals = "等于", atLeast = "不小于", atMost = "不大于", between = "介于", before = "早于", after = "晚于"
    static func allowed(for type: AudienceFieldType) -> [Self] {
        switch type {
        case .number: [.equals, .atLeast, .atMost, .between]
        case .date: [.before, .after, .equals]
        case .category, .boolean: [.equals]
        }
    }
}

enum AudienceRuleValue: Hashable {
    case number(Double), range(Double, Double), category(String), date(Date), boolean(Bool)
    var text: String {
        switch self {
        case .number(let n): n.formatted(.number.locale(DemoFormat.locale))
        case .range(let a, let b): "\(a.formatted())—\(b.formatted())"
        case .category(let s): s
        case .date(let d): DemoFormat.dateRange(start: d, end: d).components(separatedBy: "—").first ?? "—"
        case .boolean(let b): b ? "是" : "否"
        }
    }
}

struct AudienceRuleCondition: Identifiable, Hashable {
    let id: String
    /// Freeze the field definition with each saved rule.
    let field: AudienceField
    let operation: AudienceRuleOperator
    let value: AudienceRuleValue
    var summary: String { "\(field.name) \(operation.rawValue) \(value.text)" }
}

struct AudienceRules: Hashable {
    enum Relation: String, CaseIterable { case and = "AND · 全部满足", or = "OR · 任一满足" }
    var relation: Relation
    var conditions: [AudienceRuleCondition]
    var instruction: String
}

enum AudienceRecognition: String, CaseIterable {
    case recognizing = "模拟识别中", ready = "识别完成", insufficient = "依据不足", empty = "覆盖为 0"
}

struct AudienceProfileMetadata: Hashable {
    let observationPeriod: String
    let scaleVersion: String
    let categoryBasis: String
    var updatedAt: Date
    static let demo = Self(observationPeriod: "2026/07/14—2026/10/11（90日固定样本）", scaleVersion: "Demo V1 · 仅解释量表，未实现算法阈值", categoryBasis: "购买件数；正式分母待细化", updatedAt: DemoClock.referenceDate)
}

struct AudienceSnapshot: Hashable {
    var audience: Audience
    var rules: AudienceRules
    var recognition: AudienceRecognition
    var metadata: AudienceProfileMetadata
}

enum VersionObjectKind: String { case audience, plan }
enum VersionChangeSource: String { case seed = "初始样本", manualEdit = "手动保存", aiAdoption = "模拟建议采纳" }
enum VersionContent: Hashable {
    case audience(AudienceSnapshot)
    case plan(MarketingPlan)
}
struct VersionRecord: Identifiable, Hashable {
    let id: String
    let objectKind: VersionObjectKind
    let objectID: String
    let version: Int
    let createdAt: Date
    let changeSource: VersionChangeSource
    let summary: String
    var content: VersionContent
}

enum SuggestionStatus: String { case pending = "待处理", adopted = "已采纳", deferred = "暂不采纳", expired = "已失效" }
struct DemoSuggestion: Identifiable, Hashable {
    let id: String
    let targetKind: VersionObjectKind
    let targetID: String
    let baseVersion: Int
    let summary: String
    let evidence: String
    let expectedImpact: String
    let proposedRules: AudienceRules?
    var status: SuggestionStatus
    var generatedVersion: Int?
    var processedAt: Date?
}

enum DemoClock {
    static let referenceDate = Date(timeIntervalSince1970: 1_791_691_200) // 2026/10/11 12:00 Shanghai
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        return value
    }
}

struct DemoValidationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension AudienceScore {
    var level: String {
        guard let value, (1...5).contains(value) else { return "依据不足" }
        return ["低", "偏低", "中", "偏高", "高"][value - 1]
    }
}
extension AudienceScore.Dimension {
    var explanation: String {
        switch self {
        case .spending: "店铺内历史实付金额与客单价的表现，不代表个人财富。"
        case .frequency: "统一观察期内的购买次数与间隔，不等同购买意愿。"
        case .priceSensitivity: "购买行为受到价格和优惠影响的程度，高分不代表更优。"
        case .newProducts: "新品购买倾向；与经典款偏好独立观察。"
        case .classics: "长期在售产品的购买与持续复购倾向。"
        }
    }
}
