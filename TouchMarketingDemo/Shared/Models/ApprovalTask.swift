import Foundation

struct ApprovalTask: Identifiable, Hashable {
    let id: String
    let number: Int
    var audienceID: String
    var audienceVersion: Int
    var expectedReach: Int
    var reachState: TaskReachState
    var allocation: ABAllocation
    var approvalStatus: ApprovalStatus
    /// 待审批任务为 nil；审批状态与执行状态不能混用。
    var deliveryStatus: DeliveryStatus?
    let origin: ApprovalTaskOrigin
    let originSummary: String
    let isTest: Bool
    /// 生成时的推荐比例，恢复推荐时回到这里，不随当前草稿覆盖。
    let recommendedAllocation: ABAllocation
    let ruleID: String?
    let generationCycleKey: String?

    init(
        id: String,
        number: Int,
        audienceID: String,
        audienceVersion: Int,
        expectedReach: Int,
        allocation: ABAllocation,
        approvalStatus: ApprovalStatus,
        deliveryStatus: DeliveryStatus?,
        reachState: TaskReachState = .known,
        origin: ApprovalTaskOrigin = .aiRecommendation,
        originSummary: String = "AI 推荐",
        isTest: Bool = true,
        recommendedAllocation: ABAllocation? = nil,
        ruleID: String? = nil,
        generationCycleKey: String? = nil
    ) {
        self.id = id
        self.number = number
        self.audienceID = audienceID
        self.audienceVersion = audienceVersion
        self.expectedReach = expectedReach
        self.reachState = reachState
        self.allocation = allocation
        self.approvalStatus = approvalStatus
        self.deliveryStatus = deliveryStatus
        self.origin = origin
        self.originSummary = originSummary
        self.isTest = isTest
        self.recommendedAllocation = recommendedAllocation ?? allocation
        self.ruleID = ruleID
        self.generationCycleKey = generationCycleKey
    }

    var displayName: String { DemoFormat.numbered("任务", number) }

    var sourceMark: String {
        isTest ? "\(origin.rawValue) · 测试" : origin.rawValue
    }
}

enum TaskReachState: String, Hashable {
    case known = "已核对"
    case pendingReview = "待核对"
    case zeroCoverage = "零覆盖"
    case unavailable = "不可用"
}

enum ApprovalTaskOrigin: String, Hashable {
    case aiRecommendation = "AI 推荐"
    case birthdayRule = "生日规则"
    case revisitRule = "回访规则"
    case manualTest = "手动测试"
}

enum ApprovalStatus: String, CaseIterable {
    case pending = "待审批"
    case deferred = "稍后处理"
    case confirmed = "已确认"
    case rejected = "已拒绝"
}

enum DeliveryStatus: String, CaseIterable {
    case waiting = "等待发送"
    case sending = "发送中"
    case succeeded = "发送成功"
    case partiallyFailed = "部分失败"
    case failed = "发送失败"
}

struct ABAllocation: Hashable {
    struct Group: Identifiable, Hashable {
        let planID: String
        let planVersion: Int
        let percentage: Int
        var id: String { planID }
    }
    let groups: [Group]

    /// 单方案 100%；双方案各占 1...99%，不同方案、总和 100%。
    init?(groups: [Group]) {
        guard (1...2).contains(groups.count),
              Set(groups.map(\.planID)).count == groups.count,
              groups.allSatisfy({ !$0.planID.isEmpty && $0.planVersion > 0 && (1...100).contains($0.percentage) }),
              groups.reduce(0, { $0 + $1.percentage }) == 100 else { return nil }
        self.groups = groups
    }

    /// 最后一组取余数，确保两组人数相加等于任务人数。
    func expectedCounts(total: Int) -> [Int] {
        guard total >= 0 else { return [] }
        if groups.count == 1 { return [total] }
        let first = Int((Double(total) * Double(groups[0].percentage) / 100).rounded(.down))
        return [first, total - first]
    }
}

enum ApprovalActionResult: Equatable {
    case saved(String)
    case unchanged(String)
    case failed(String)

    var message: String {
        switch self {
        case .saved(let text), .unchanged(let text), .failed(let text): text
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
