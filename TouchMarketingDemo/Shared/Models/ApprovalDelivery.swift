import Foundation

/// 确认当时冻结的内容。已发送页面读这份快照，不读人群或方案的最新正文。
struct DeliverySnapshot: Identifiable, Hashable {
    struct Group: Identifiable, Hashable {
        let planID: String
        let planVersion: Int
        let planNumber: Int
        let purpose: PlanPurpose
        let customerStage: CustomerStage
        let message: String
        let resourceSummary: String
        let resourceWasValid: Bool
        let percentage: Int
        let allocatedCount: Int
        var id: String { planID }
        var displayName: String { DemoFormat.numbered("方案", planNumber) }
    }

    let id: String
    let taskID: String
    let batchID: String
    let confirmedAt: Date
    /// 统计用的演示业务日，不是操作留痕的实际时间。
    let businessDate: Date
    let origin: ApprovalTaskOrigin
    let originSummary: String
    let audienceID: String
    let audienceNumber: Int
    let audienceVersion: Int
    let memberCount: Int
    let scores: [AudienceScore]
    let expectedReach: Int
    let dedupNote: String
    let groups: [Group]

    var audienceDisplayName: String { DemoFormat.numbered("人群", audienceNumber) }
}

struct GroupDeliveryCount: Identifiable, Hashable {
    let planID: String
    let allocated: Int
    var succeeded: Int
    var failed: Int
    var id: String { planID }
}

enum DeliveryPreset: String, Hashable, CaseIterable {
    case succeeded = "发送成功"
    case partiallyFailed = "部分失败"
    case failed = "全部失败"
}

enum RetryPreset: String, Hashable, CaseIterable {
    case allSucceeded = "全部补发成功"
    case stillPartial = "仍部分失败"
}

enum StatisticsReadiness: String, Hashable {
    /// 新批次的成交未知，不能写成 0，也不能抄历史成交。
    case collecting = "统计中"
    case historicalSample = "历史模拟统计"
    case simulated = "已载入模拟统计"
}

struct DeliveryBatch: Identifiable, Hashable {
    let id: String
    let taskID: String
    let snapshotID: String
    let businessDate: Date
    var status: DeliveryStatus
    var groups: [GroupDeliveryCount]
    var retryCount: Int
    var failureReason: String?
    var startedAt: Date?
    var finishedAt: Date?
    var preset: DeliveryPreset
    var retryPreset: RetryPreset
    var isRetryInFlight: Bool
    var statisticsStatus: StatisticsReadiness

    var succeededTotal: Int { groups.reduce(0) { $0 + $1.succeeded } }
    var failedTotal: Int { groups.reduce(0) { $0 + $1.failed } }
    var allocatedTotal: Int { groups.reduce(0) { $0 + $1.allocated } }

    mutating func applyInitialPreset(now: Date) {
        switch preset {
        case .succeeded:
            for index in groups.indices {
                groups[index].succeeded = groups[index].allocated
                groups[index].failed = 0
            }
            status = .succeeded
            failureReason = nil
        case .partiallyFailed:
            for index in groups.indices {
                let split = ApprovalExecutionMath.partialFailure(allocated: groups[index].allocated)
                groups[index].succeeded = split.succeeded
                groups[index].failed = split.failed
            }
            status = .partiallyFailed
            failureReason = "演示预设：部分客户模拟发送失败"
        case .failed:
            for index in groups.indices {
                groups[index].succeeded = 0
                groups[index].failed = groups[index].allocated
            }
            status = .failed
            failureReason = "演示预设：本轮模拟发送失败"
        }
        finishedAt = now
        isRetryInFlight = false
        if statisticsStatus != .historicalSample {
            statisticsStatus = .collecting
        }
    }

    mutating func applyRetry(now: Date) {
        switch retryPreset {
        case .allSucceeded:
            for index in groups.indices {
                groups[index].succeeded = groups[index].allocated
                groups[index].failed = 0
            }
            status = groups.isEmpty ? .failed : .succeeded
            failureReason = nil
        case .stillPartial:
            var anyFailed = false
            for index in groups.indices {
                let recovered = ApprovalExecutionMath.retryRecovered(failed: groups[index].failed)
                groups[index].succeeded += recovered
                groups[index].failed -= recovered
                if groups[index].failed > 0 { anyFailed = true }
            }
            status = anyFailed ? .partiallyFailed : .succeeded
            failureReason = anyFailed ? "演示预设：重试后仍有部分失败" : nil
        }
        retryCount += 1
        isRetryInFlight = false
        finishedAt = now
        if statisticsStatus != .historicalSample {
            statisticsStatus = .collecting
        }
    }
}

enum ApprovalRecordKind: String, Hashable {
    case generate = "生成任务"
    case changeAudience = "更换人群"
    case changePlan = "更换方案"
    case changeAllocation = "调整比例"
    case deferTask = "稍后处理"
    case rejectTask = "拒绝"
    case confirm = "人工确认"
    case simulationStart = "模拟开始"
    case simulationFinish = "模拟结束"
    case retry = "重试"
}

struct ApprovalRecord: Identifiable, Hashable {
    let id: String
    let serial: Int
    let taskID: String
    let kind: ApprovalRecordKind
    let at: Date
    let beforeSummary: String
    let afterSummary: String
    let note: String
    let operatorName: String
}

/// B 生成待审批时传入。同一 ruleID + cycleKey 只创建一条任务。
struct RulePendingTaskRequest: Equatable {
    let ruleID: String
    let cycleKey: String
    let origin: ApprovalTaskOrigin
    let summary: String
    let audienceID: String
    let audienceVersion: Int
    let expectedReach: Int
    let allocation: ABAllocation
}

/// D 读取触达计数的只读投影。不含成交人数；成交未知时看 statisticsStatus。
struct DeliveryTouchSummary: Identifiable, Hashable {
    struct Group: Identifiable, Hashable {
        let planID: String
        let planVersion: Int
        let allocated: Int
        let succeeded: Int
        var id: String { planID }
    }

    let batchID: String
    let taskID: String
    let businessDate: Date
    let audienceID: String
    let audienceVersion: Int
    let statisticsStatus: StatisticsReadiness
    let groups: [Group]
    var id: String { batchID }
}

enum ApprovalExecutionMath {
    static let dedupNote = "演示约定：去重先于分组。本 Demo 不持有客户名单，人数是固定样本，不是客户级去重结果。"
    static let operatorName = "演示运营人员"

    /// 失败人数取分配的 1/4，600／1,400 正好得到 150／350。
    static func partialFailure(allocated: Int) -> (succeeded: Int, failed: Int) {
        guard allocated > 0 else { return (0, 0) }
        let failed = max(1, allocated / 4)
        return (allocated - failed, failed)
    }

    /// 失败至少 2 人时补回一半，剩余失败一定会变少，且不会变成全部成功。
    static func retryRecovered(failed: Int) -> Int {
        guard failed >= 2 else { return 0 }
        return max(1, failed / 2)
    }

    static func verify() -> [String] {
        var errors: [String] = []
        let thirty = ABAllocation(groups: [
            .init(planID: "plan-01", planVersion: 1, percentage: 30),
            .init(planID: "plan-02", planVersion: 1, percentage: 70)
        ])
        if thirty?.expectedCounts(total: 2_000) != [600, 1_400] { errors.append("30/70 应为 600/1400") }
        let half = ABAllocation(groups: [
            .init(planID: "plan-01", planVersion: 1, percentage: 50),
            .init(planID: "plan-02", planVersion: 1, percentage: 50)
        ])
        if half?.expectedCounts(total: 2_000) != [1_000, 1_000] { errors.append("50/50 应为 1000/1000") }
        if ABAllocation(groups: [
            .init(planID: "plan-01", planVersion: 1, percentage: 0),
            .init(planID: "plan-02", planVersion: 1, percentage: 100)
        ]) != nil { errors.append("0/100 应被拒绝") }
        if ABAllocation(groups: [
            .init(planID: "plan-01", planVersion: 1, percentage: 50),
            .init(planID: "plan-01", planVersion: 1, percentage: 50)
        ]) != nil { errors.append("同方案应被拒绝") }
        if ABAllocation(groups: [
            .init(planID: "a", planVersion: 1, percentage: 20),
            .init(planID: "b", planVersion: 1, percentage: 30),
            .init(planID: "c", planVersion: 1, percentage: 50)
        ]) != nil { errors.append("第三套方案应被拒绝") }
        let partA = partialFailure(allocated: 600)
        let partB = partialFailure(allocated: 1_400)
        if partA.succeeded != 450 || partA.failed != 150 || partB.succeeded != 1_050 || partB.failed != 350 {
            errors.append("部分失败样本应为 450/150 与 1050/350")
        }
        let recoveredA = retryRecovered(failed: 150)
        let recoveredB = retryRecovered(failed: 350)
        if recoveredA != 75 || recoveredB != 175 { errors.append("重试补回人数不正确") }
        let afterPartialRetry = partA.succeeded + recoveredA + partB.succeeded + recoveredB
        if afterPartialRetry != 1_750 { errors.append("仍部分失败后的成功人数应为 1750") }
        if partA.succeeded + partA.failed + partB.succeeded + partB.failed != 2_000 {
            errors.append("部分失败合计应仍为 2000")
        }
        let small = ABAllocation(groups: [
            .init(planID: "plan-01", planVersion: 1, percentage: 1),
            .init(planID: "plan-02", planVersion: 1, percentage: 99)
        ])
        if small?.expectedCounts(total: 50) != [0, 50] { errors.append("小样本 1% 应出现 0 人组") }
        if ApprovalAllocationRules.validate(
            slots: [ApprovalSlotInput(planID: "plan-01", planVersion: 1)],
            primaryPercentText: "100", reach: 2_000
        ) != nil { errors.append("单方案应可通过") }
        if ApprovalAllocationRules.validate(
            slots: [
                ApprovalSlotInput(planID: "plan-01", planVersion: 1),
                ApprovalSlotInput(planID: "plan-02", planVersion: 1)
            ],
            primaryPercentText: "0", reach: 2_000
        ) == nil { errors.append("0% 应被阻止") }
        if ApprovalAllocationRules.validate(
            slots: [
                ApprovalSlotInput(planID: "plan-01", planVersion: 1),
                ApprovalSlotInput(planID: "plan-02", planVersion: 1)
            ],
            primaryPercentText: "", reach: 2_000
        ) == nil { errors.append("空百分比应被阻止") }
        if ApprovalAllocationRules.make(
            slots: [
                ApprovalSlotInput(planID: "plan-01", planVersion: 1),
                ApprovalSlotInput(planID: "plan-02", planVersion: 1)
            ],
            primaryPercentText: "50"
        )?.expectedCounts(total: 2_000) != [1_000, 1_000] { errors.append("输入 50 应得到 1000/1000") }
        return errors
    }
}
