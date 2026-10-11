import Foundation

// B 提供的增量领域契约，供 A 集中评审合入；不改变现有模型初始化接口。
enum ResourceKind: String, CaseIterable, Hashable {
    case coupon = "优惠券", product = "商品", lottery = "抽奖"
}

struct StoreResource: Identifiable, Hashable {
    let id: String
    let kind: ResourceKind
    let name: String
    let detail: String
    let amountInCents: Int?
    let minimumSpendInCents: Int?
    let category: String?
    let validFrom: Date
    let validThrough: Date
    let unavailableReason: String?
    let demoURL: String?

    func invalidReason(on date: Date) -> String? {
        if let unavailableReason { return unavailableReason }
        if date < validFrom { return "尚未到有效期" }
        if date > validThrough { return "已超过有效期" }
        return nil
    }
}

/// 内容值可用于局部草稿；提交后由唯一 DemoSession 持有。
struct PlanContent: Hashable {
    var purpose: PlanPurpose = .repurchase
    var customerStage: CustomerStage = .purchased
    var message: String = ""
    var resourceID: String?
    var audienceIDs: [String] = []

    init(purpose: PlanPurpose = .repurchase, customerStage: CustomerStage = .purchased,
         message: String = "", resourceID: String? = nil, audienceIDs: [String] = []) {
        self.purpose = purpose
        self.customerStage = customerStage
        self.message = message
        self.resourceID = resourceID
        self.audienceIDs = audienceIDs
    }

    init(plan: MarketingPlan, resourceID: String?) {
        self.init(purpose: plan.purpose, customerStage: plan.customerStage,
                  message: plan.message, resourceID: resourceID, audienceIDs: plan.audienceIDs)
    }

    var normalized: Self {
        var copy = self
        copy.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.audienceIDs = Array(Set(audienceIDs)).sorted()
        return copy
    }
}

struct PlanMetadata: Hashable {
    let resourceID: String?
    let createdAt: Date
    let updatedAt: Date
}

enum PlanChangeSource: String, Hashable {
    case initial = "初始版本", manual = "手动编辑", aiAdoption = "AI 建议采纳"
}

/// 类型化内容快照，A 可将元信息接入统一 VersionRecord，不能重读最新资源充当历史。
struct PlanVersionSnapshot: Identifiable, Hashable {
    let plan: MarketingPlan
    let metadata: PlanMetadata
    let resource: StoreResource?
    let resourceCheckedAt: Date
    let changedAt: Date
    let changeSource: PlanChangeSource
    let summary: String
    var id: String { "\(plan.id)-v\(plan.version)" }
}

enum PlanSuggestionStatus: String, Hashable {
    case pending = "待处理", adopted = "已采纳", deferred = "暂不采纳"
}

struct PlanSuggestion: Identifiable, Hashable {
    let id: String
    let planID: String
    let baseVersion: Int
    let proposed: PlanContent
    let evidenceStart: Date
    let evidenceEnd: Date
    let reason: String
    let expectedImpact: String
    var status: PlanSuggestionStatus = .pending
    var handledAt: Date?
    var resultingVersion: Int?
}

struct PlanTemplate: Identifiable, Hashable {
    let id: String
    let title: String
    let content: PlanContent
}

enum TouchRuleKind: String, CaseIterable, Hashable {
    case birthday = "生日规则", followUp = "定期回访"
}

enum FollowUpPeriod: Int, CaseIterable, Hashable {
    case threeMonths = 3, sixMonths = 6
    var title: String { self == .threeMonths ? "三个月" : "六个月" }
}

struct TouchRuleConfiguration: Hashable {
    var kind: TouchRuleKind = .birthday
    var isEnabled = true
    var period: FollowUpPeriod = .threeMonths
    var hour = 9
    var minute = 0
    var primaryPlanID = ""
    var secondaryPlanID: String?
    var primaryPercentage = 100
    var timeLabel: String { String(format: "%02d:%02d", hour, minute) }
    var conditionLabel: String {
        kind == .birthday ? "参考日当天生日（本地样本假设）" : "最近一次购买满\(period.title)（演示约定）"
    }
}

struct TouchRule: Identifiable, Hashable {
    let id: String
    let number: Int
    let revision: Int
    let configuration: TouchRuleConfiguration
    let updatedAt: Date
    var displayName: String { DemoFormat.numbered("规则", number) }
}

/// 预去重的固定范围；不声称在本机执行了客户级计算。
struct PlanRuleRange: Hashable {
    let kind: TouchRuleKind
    let period: FollowUpPeriod?
    let audienceID: String
    let expectedReach: Int
    let summary: String
}

struct PlanRulePreview: Hashable {
    let rule: TouchRule
    let referenceDate: Date
    let cycleID: String
    let audience: Audience
    let expectedReach: Int
    let scopeSummary: String
    let cutoffDate: Date?
    let allocation: ABAllocation
    let plans: [PlanVersionSnapshot]
    var deduplicationKey: String { "\(rule.id)|\(cycleID)" }
}

struct PlanRuleGeneration: Identifiable, Hashable {
    let taskID: String
    let taskNumber: Int
    let createdAt: Date
    let preview: PlanRulePreview
    var id: String { preview.deduplicationKey }
}

struct PlanSaveRequest {
    // 草稿打开时生成一次。A 应按此 ID 保证新建请求幂等，不在点击时再生成 ID。
    let id: String
    let baseVersion: Int?
    let content: PlanContent
    let creationSource: CreationSource
}

struct PlanRevision {
    let plan: MarketingPlan
    let metadata: PlanMetadata
    let snapshot: PlanVersionSnapshot
}

struct PlanValidationError: LocalizedError, Equatable {
    let messages: [String]
    var errorDescription: String? { messages.joined(separator: "\n") }
    init(_ message: String) { messages = [message] }
    init(messages: [String]) { self.messages = messages }
}

/// A 的唯一 @Observable DemoSession 实现此接口；此处没有创建第二份 store。
/// 所有写入在 MainActor 同步校验并原子提交，C 的生成操作必须先落入审批任务再返回。
@MainActor
protocol PlanSessionAccess: AnyObject {
    var plans: [MarketingPlan] { get }
    var audiences: [Audience] { get }
    var planMetadata: [String: PlanMetadata] { get }
    var planVersions: [PlanVersionSnapshot] { get }
    var storeResources: [StoreResource] { get }
    var planTemplates: [PlanTemplate] { get }
    var planSuggestions: [PlanSuggestion] { get }
    var touchRules: [TouchRule] { get }
    var ruleGenerations: [PlanRuleGeneration] { get }
    var planRuleRanges: [PlanRuleRange] { get }
    var planReferenceDate: Date { get }
    var planRecommendedPrimaryPercentage: Int { get }
    var ruleGenerationAvailable: Bool { get }

    @discardableResult func savePlan(_ request: PlanSaveRequest) throws -> MarketingPlan
    @discardableResult func adoptPlanSuggestion(id: String) throws -> MarketingPlan
    func deferPlanSuggestion(id: String) throws
    @discardableResult func saveTouchRule(id: String, baseRevision: Int?, configuration: TouchRuleConfiguration) throws -> TouchRule
    func setTouchRuleEnabled(id: String, baseRevision: Int, enabled: Bool) throws
    func generatePendingTask(from preview: PlanRulePreview) throws -> PlanRuleGeneration
}
