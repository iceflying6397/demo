import Foundation
import Observation

/// 全 App 一份会话。审批在这里保存任务、快照、批次和记录。
/// 人群、方案、数据页仍读取原来的只读 store，直到整合者把它们也接到这份会话。
@MainActor
@Observable
final class DemoSession {
    private let seed: MockDataStore
    private(set) var audiences: [Audience] = []
    private(set) var plans: [MarketingPlan] = []
    private(set) var tasks: [ApprovalTask] = []
    private(set) var records: [ApprovalRecord] = []
    private(set) var snapshots: [DeliverySnapshot] = []
    private(set) var batches: [DeliveryBatch] = []
    private(set) var analytics: AnalyticsSummary
    private(set) var resetGeneration = 0

    private var audienceRevisions: [String: Audience] = [:]
    private var planRevisions: [String: MarketingPlan] = [:]
    private var revisionNotes: [String: String] = [:]
    private var reachFixtures: [String: Int] = [:]
    private var resourceValid: [String: Bool] = [:]
    private var resourceReasons: [String: String] = [:]
    private var numberCursor = 3
    private var recordSerial = 1
    private static var didVerify = false

    /// 2026/10/11 00:00 Asia/Shanghai。新批次的统计业务日用它，操作记录另记实际时间。
    static let referenceDate = Date(timeIntervalSince1970: 1_791_648_000)

    init(seed: MockDataStore = .demo, verify: Bool = true) {
        self.seed = seed
        self.analytics = seed.analytics
        load(seed)
        guard verify, !Self.didVerify else { return }
        Self.didVerify = true
        var errors = ApprovalExecutionMath.verify()
        let probe = DemoSession(seed: seed, verify: false)
        errors.append(contentsOf: probe.verifyRuleGate())
        if !errors.isEmpty {
            assertionFailure(errors.joined(separator: " | "))
        }
    }

    func reset() {
        load(seed)
        resetGeneration += 1
    }

    func task(id: String) -> ApprovalTask? { tasks.first { $0.id == id } }
    func audience(id: String) -> Audience? { audiences.first { $0.id == id } }
    func plan(id: String) -> MarketingPlan? { plans.first { $0.id == id } }
    func audienceRevision(id: String, version: Int) -> Audience? { audienceRevisions[revisionKey(id, version)] }
    func planRevision(id: String, version: Int) -> MarketingPlan? { planRevisions[revisionKey(id, version)] }
    func snapshot(for taskID: String) -> DeliverySnapshot? { snapshots.first { $0.taskID == taskID } }
    func batch(for taskID: String) -> DeliveryBatch? { batches.first { $0.taskID == taskID } }
    func batch(id: String) -> DeliveryBatch? { batches.first { $0.id == id } }

    func records(for taskID: String?) -> [ApprovalRecord] {
        let matched = taskID.map { id in records.filter { $0.taskID == id } } ?? records
        return matched.sorted { lhs, rhs in
            lhs.at == rhs.at ? lhs.serial < rhs.serial : lhs.at < rhs.at
        }
    }

    func rejectedTasks() -> [ApprovalTask] {
        tasks.filter { $0.approvalStatus == .rejected }.sorted { $0.number < $1.number }
    }

    func knownReach(audienceID: String, version: Int) -> Int? {
        reachValue(audienceID: audienceID, version: version)
    }

    func reachAssessment(audienceID: String, version: Int) -> TaskReachState {
        guard let audience = audienceRevision(id: audienceID, version: version) else { return .unavailable }
        if audience.memberCount <= 0 { return .zeroCoverage }
        guard let reach = reachFixtures[revisionKey(audienceID, version)] else { return .pendingReview }
        return reach <= 0 ? .zeroCoverage : .known
    }

    func reachValue(audienceID: String, version: Int) -> Int? {
        let key = revisionKey(audienceID, version)
        guard let reach = reachFixtures[key], reach > 0,
              audienceRevision(id: audienceID, version: version)?.memberCount ?? 0 > 0 else { return nil }
        return reach
    }

    func isResourceValid(planID: String) -> Bool { resourceValid[planID] != false && plan(id: planID) != nil }

    func resourceInvalidReason(planID: String) -> String? {
        guard !isResourceValid(planID: planID) else { return nil }
        return resourceReasons[planID] ?? "资源已失效。请到方案模块替换或选择可用版本。"
    }

    func versionDifferences(for task: ApprovalTask) -> [String] {
        var lines: [String] = []
        if let current = audience(id: task.audienceID), current.version != task.audienceVersion {
            let note = revisionNotes[revisionKey(task.audienceID, current.version)] ?? "内容已更新"
            lines.append("\(current.displayName)：任务使用 V\(task.audienceVersion)，当前是 V\(current.version)。\(note)")
        } else if audience(id: task.audienceID) == nil {
            lines.append("任务引用的人群已不在目录中。")
        }
        for group in task.allocation.groups {
            if let current = plan(id: group.planID), current.version != group.planVersion {
                let note = revisionNotes[revisionKey(group.planID, current.version)] ?? "内容已更新"
                lines.append("\(current.displayName)：任务使用 V\(group.planVersion)，当前是 V\(current.version)。\(note)")
            }
        }
        return lines
    }

    func pinnedContentAvailable(_ task: ApprovalTask) -> Bool {
        guard audienceRevision(id: task.audienceID, version: task.audienceVersion) != nil else { return false }
        return task.allocation.groups.allSatisfy { planRevision(id: $0.planID, version: $0.planVersion) != nil }
    }

    func confirmIssues(taskID: String) -> [String] {
        guard let task = task(id: taskID) else { return ["任务不存在。"] }
        if snapshots.contains(where: { $0.taskID == taskID }) { return [] }
        var issues: [String] = []
        if task.approvalStatus != .pending && task.approvalStatus != .deferred {
            issues.append("当前状态不能确认发送。")
        }
        if audienceRevision(id: task.audienceID, version: task.audienceVersion) == nil {
            issues.append("找不到任务引用的人群版本，不能用最新人群冒充旧版本。")
        }
        switch reachAssessment(audienceID: task.audienceID, version: task.audienceVersion) {
        case .known:
            if task.reachState != .known || task.expectedReach <= 0 {
                issues.append("本次人数尚未核对，不能确认发送。")
            }
        case .pendingReview:
            issues.append("本次人数待核对，不能编造可发送人数。")
        case .zeroCoverage:
            issues.append("人群是零覆盖，不能确认发送。")
        case .unavailable:
            issues.append("人群不可用，不能确认发送。")
        }
        for group in task.allocation.groups {
            if planRevision(id: group.planID, version: group.planVersion) == nil {
                issues.append("找不到方案版本，不能确认发送。")
            }
            if !isResourceValid(planID: group.planID) {
                let name = plan(id: group.planID)?.displayName ?? "方案"
                issues.append("\(name) 资源已失效。继续旧版本不能绕过。请到方案模块替换或选择可用版本。")
            }
        }
        if task.reachState == .known, task.expectedReach > 0,
           task.allocation.expectedCounts(total: task.expectedReach).contains(0) {
            issues.append("某一组预计人数为 0，不能按双组确认。")
        }
        return issues
    }

    func touchSummaries() -> [DeliveryTouchSummary] {
        batches.compactMap { batch in
            guard let snapshot = snapshots.first(where: { $0.id == batch.snapshotID }) else { return nil }
            let groups = snapshot.groups.compactMap { frozen -> DeliveryTouchSummary.Group? in
                guard let count = batch.groups.first(where: { $0.planID == frozen.planID }) else { return nil }
                return .init(planID: frozen.planID, planVersion: frozen.planVersion,
                             allocated: count.allocated, succeeded: count.succeeded)
            }
            return DeliveryTouchSummary(
                batchID: batch.id, taskID: batch.taskID, businessDate: batch.businessDate,
                audienceID: snapshot.audienceID, audienceVersion: snapshot.audienceVersion,
                statisticsStatus: batch.statisticsStatus, groups: groups
            )
        }
    }

    func saveAdjustment(
        taskID: String, audienceID: String, audienceVersion: Int,
        allocation: ABAllocation, now: Date = Date()
    ) -> ApprovalActionResult {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return .failed("任务不存在。") }
        let task = tasks[index]
        guard task.approvalStatus == .pending || task.approvalStatus == .deferred else {
            return .failed("已确认或已拒绝的任务不能再调整。")
        }
        let slots = allocation.groups.map { ApprovalSlotInput(planID: $0.planID, planVersion: $0.planVersion) }
        let percentText = allocation.groups.count == 2 ? String(allocation.groups[0].percentage) : "100"
        let reach = reachValue(audienceID: audienceID, version: audienceVersion)
        if let message = ApprovalAllocationRules.validate(slots: slots, primaryPercentText: percentText, reach: reach) {
            return .failed(message)
        }
        guard audienceRevision(id: audienceID, version: audienceVersion) != nil else {
            return .failed("找不到所选人群版本。")
        }
        guard allocation.groups.allSatisfy({ planRevision(id: $0.planID, version: $0.planVersion) != nil }) else {
            return .failed("找不到所选方案版本。")
        }
        let assessment = storedAssessment(audienceID: audienceID, version: audienceVersion)
        let audienceChanged = task.audienceID != audienceID || task.audienceVersion != audienceVersion
        let plansChanged = task.allocation.groups.map(\.planID) != allocation.groups.map(\.planID)
            || task.allocation.groups.map(\.planVersion) != allocation.groups.map(\.planVersion)
        let percentChanged = task.allocation.groups.map(\.percentage) != allocation.groups.map(\.percentage)
        if !audienceChanged && !plansChanged && !percentChanged && task.reachState == assessment {
            return .unchanged("没有变化，未写入记录。")
        }
        let beforeAudience = audienceText(id: task.audienceID, version: task.audienceVersion, reach: task.expectedReach, state: task.reachState)
        tasks[index].audienceID = audienceID
        tasks[index].audienceVersion = audienceVersion
        writeReach(index: index, audienceID: audienceID, version: audienceVersion)
        let beforePlans = planText(task.allocation)
        let beforePercent = percentTextSummary(task.allocation, reach: task.expectedReach, state: task.reachState)
        tasks[index].allocation = allocation
        let saved = tasks[index]
        if audienceChanged {
            appendRecord(taskID: taskID, kind: .changeAudience, at: now,
                         before: beforeAudience,
                         after: audienceText(id: saved.audienceID, version: saved.audienceVersion, reach: saved.expectedReach, state: saved.reachState),
                         note: "只更换本次任务引用，没有修改人群规则。")
        }
        if plansChanged {
            appendRecord(taskID: taskID, kind: .changePlan, at: now, before: beforePlans,
                         after: planText(allocation), note: "只更换本次任务的方案和版本。")
        }
        if percentChanged {
            appendRecord(taskID: taskID, kind: .changeAllocation, at: now, before: beforePercent,
                         after: percentTextSummary(allocation, reach: saved.expectedReach, state: saved.reachState),
                         note: "推荐比例仍保持原值。")
        }
        return .saved("已保存本次任务配置。")
    }

    func deferTask(taskID: String, now: Date = Date()) -> ApprovalActionResult {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return .failed("任务不存在。") }
        if tasks[index].approvalStatus == .deferred { return .unchanged("已经是稍后处理，未重复记录。") }
        guard tasks[index].approvalStatus == .pending else { return .failed("当前状态不能稍后处理。") }
        let before = tasks[index].approvalStatus.rawValue
        tasks[index].approvalStatus = .deferred
        appendRecord(taskID: taskID, kind: .deferTask, at: now, before: before, after: ApprovalStatus.deferred.rawValue,
                     note: "仍在待审批中，不会发送。")
        return .saved("已标为稍后处理。")
    }

    func rejectTask(taskID: String, reason: String, now: Date = Date()) -> ApprovalActionResult {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return .failed("任务不存在。") }
        guard tasks[index].approvalStatus == .pending || tasks[index].approvalStatus == .deferred else {
            return .failed("当前状态不能拒绝。")
        }
        guard batches.contains(where: { $0.taskID == taskID }) == false else {
            return .failed("已有发送批次的任务不能改成拒绝。")
        }
        let task = tasks[index]
        let before = "\(task.approvalStatus.rawValue) · \(planText(task.allocation))"
        tasks[index].approvalStatus = .rejected
        tasks[index].deliveryStatus = nil
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        appendRecord(taskID: taskID, kind: .rejectTask, at: now, before: before,
                     after: "已拒绝 · \(audienceText(id: task.audienceID, version: task.audienceVersion, reach: task.expectedReach, state: task.reachState))",
                     note: trimmed.isEmpty ? "未填写原因。未创建发送批次。" : "原因：\(trimmed)。未创建发送批次。")
        return .saved("已拒绝。任务已从待审批移除，记录仍可查看。")
    }

    func updateToCurrentVersions(taskID: String, now: Date = Date()) -> ApprovalActionResult {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return .failed("任务不存在。") }
        guard tasks[index].approvalStatus == .pending || tasks[index].approvalStatus == .deferred else {
            return .failed("已确认或已拒绝的任务不能更新版本。")
        }
        var task = tasks[index]
        var audienceChanged = false
        var plansChanged = false
        let beforeAudience = audienceText(id: task.audienceID, version: task.audienceVersion, reach: task.expectedReach, state: task.reachState)
        if let current = audience(id: task.audienceID), current.version != task.audienceVersion {
            task.audienceVersion = current.version
            audienceChanged = true
        }
        var groups = task.allocation.groups
        for groupIndex in groups.indices {
            if let current = plan(id: groups[groupIndex].planID), current.version != groups[groupIndex].planVersion {
                groups[groupIndex] = .init(planID: groups[groupIndex].planID, planVersion: current.version, percentage: groups[groupIndex].percentage)
                plansChanged = true
            }
        }
        guard audienceChanged || plansChanged else { return .unchanged("已经是当前版本，未写入记录。") }
        guard let allocation = ABAllocation(groups: groups) else { return .failed("更新后的分配无效。") }
        let beforePlans = planText(tasks[index].allocation)
        tasks[index].audienceVersion = task.audienceVersion
        tasks[index].allocation = allocation
        writeReach(index: index, audienceID: tasks[index].audienceID, version: tasks[index].audienceVersion)
        let saved = tasks[index]
        if audienceChanged {
            appendRecord(taskID: taskID, kind: .changeAudience, at: now, before: beforeAudience,
                         after: audienceText(id: saved.audienceID, version: saved.audienceVersion, reach: saved.expectedReach, state: saved.reachState),
                         note: "已改到当前人群版本，需要重新核对后才能发送。")
        }
        if plansChanged {
            appendRecord(taskID: taskID, kind: .changePlan, at: now, before: beforePlans, after: planText(allocation),
                         note: "已改到当前方案版本，需要重新核对后才能发送。")
        }
        return .saved("已更新到当前版本。尚未发送，请重新核对。")
    }

    func confirmSend(
        taskID: String, preset: DeliveryPreset, acknowledgeVersionGap: Bool, now: Date = Date()
    ) -> ApprovalActionResult {
        if taskID == "task-history-01" { return .failed("历史任务的固定结果不能被覆盖。") }
        if snapshots.contains(where: { $0.taskID == taskID }) || batches.contains(where: { $0.taskID == taskID }) {
            return .unchanged("已经确认，未创建新的快照或批次。")
        }
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return .failed("任务不存在。") }
        let task = tasks[index]
        if !versionDifferences(for: task).isEmpty && !acknowledgeVersionGap {
            return .failed("版本与当前目录不一致。请先选择继续原版本，或更新到当前版本后重新核对。")
        }
        let issues = confirmIssues(taskID: taskID)
        if let first = issues.first { return .failed(first) }
        guard let snapshot = makeSnapshot(task: task, batchID: "batch-\(task.id)", at: now) else {
            return .failed("无法冻结快照。")
        }
        guard snapshot.batchID != "batch-history-01" else { return .failed("批次编号与历史样本冲突。") }
        let batch = DeliveryBatch(
            id: snapshot.batchID, taskID: task.id, snapshotID: snapshot.id, businessDate: Self.referenceDate,
            status: .waiting,
            groups: snapshot.groups.map {
                GroupDeliveryCount(planID: $0.planID, allocated: $0.allocatedCount, succeeded: 0, failed: 0)
            },
            retryCount: 0, failureReason: nil, startedAt: nil, finishedAt: nil,
            preset: preset, retryPreset: .allSucceeded, isRetryInFlight: false,
            statisticsStatus: .collecting
        )
        snapshots.append(snapshot)
        batches.append(batch)
        tasks[index].approvalStatus = .confirmed
        tasks[index].deliveryStatus = .waiting
        appendRecord(taskID: taskID, kind: .confirm, at: now,
                     before: task.approvalStatus.rawValue,
                     after: "已确认 · 等待发送 · \(snapshot.batchID)",
                     note: "本地模拟。成交数据为统计中，未写入历史样本。")
        return .saved("已确认并创建批次 \(snapshot.batchID)。当前是等待发送，尚未执行。")
    }

    func setInitialPreset(batchID: String, preset: DeliveryPreset) -> ApprovalActionResult {
        guard let index = batches.firstIndex(where: { $0.id == batchID }) else { return .failed("批次不存在。") }
        if batches[index].taskID == "task-history-01" { return .failed("历史样本的结果不能改。") }
        if batches[index].isRetryInFlight { return .failed("重试执行中，不能改初始结果。") }
        switch batches[index].status {
        case .waiting, .sending:
            batches[index].preset = preset
            return .saved("演示结果已选为\(preset.rawValue)。还没有执行。")
        case .succeeded, .partiallyFailed, .failed:
            return .failed("执行已经结束，不能改预设结果。")
        }
    }

    func advance(batchID: String, now: Date = Date()) -> ApprovalActionResult {
        guard let index = batches.firstIndex(where: { $0.id == batchID }) else { return .failed("批次不存在。") }
        if batches[index].taskID == "task-history-01" { return .failed("历史固定结果不能再次推进。") }
        let taskID = batches[index].taskID
        switch batches[index].status {
        case .waiting:
            if let blocker = resourceBlocker(taskID: taskID) { return .failed(blocker) }
            batches[index].status = .sending
            batches[index].startedAt = now
            setDelivery(taskID, .sending)
            appendRecord(taskID: taskID, kind: .simulationStart, at: now, before: DeliveryStatus.waiting.rawValue,
                         after: DeliveryStatus.sending.rawValue, note: "演示控制：开始模拟执行。")
            return .saved("已进入发送中。此期间不能再次确认，也不能并行重试。")
        case .sending:
            let retrying = batches[index].isRetryInFlight
            if retrying {
                batches[index].applyRetry(now: now)
            } else {
                batches[index].applyInitialPreset(now: now)
            }
            let batch = batches[index]
            setDelivery(taskID, batch.status)
            appendRecord(taskID: taskID, kind: .simulationFinish, at: now, before: DeliveryStatus.sending.rawValue,
                         after: "\(batch.status.rawValue) · 成功 \(batch.succeededTotal) · 失败 \(batch.failedTotal)",
                         note: retrying ? "重试只更新原批次。成功人数不会把已成功客户再加一次。" : "演示控制：按预设结果结束。成交仍是统计中。")
            return .saved("模拟结束：\(batch.status.rawValue)。成功 \(DemoFormat.count(batch.succeededTotal)) 人，失败 \(DemoFormat.count(batch.failedTotal)) 人。")
        case .succeeded, .partiallyFailed, .failed:
            return .failed("当前不在可推进状态，不会重复执行。")
        }
    }

    func startRetry(batchID: String, preset: RetryPreset, now: Date = Date()) -> ApprovalActionResult {
        guard let index = batches.firstIndex(where: { $0.id == batchID }) else { return .failed("批次不存在。") }
        if batches[index].taskID == "task-history-01" { return .failed("历史成功样本没有失败范围。") }
        if batches[index].status == .sending || batches[index].isRetryInFlight {
            return .failed("执行中不能重复重试。")
        }
        guard batches[index].status == .partiallyFailed || batches[index].status == .failed else {
            return .failed("当前没有可重试的失败范围。")
        }
        guard batches[index].failedTotal > 0 else { return .failed("没有剩余失败人数。") }
        if preset == .stillPartial && batches[index].groups.allSatisfy({ $0.failed < 2 }) {
            return .failed("失败人数不足 2，无法在仍部分失败时让剩余人数变化。请选择全部补发成功。")
        }
        if let blocker = resourceBlocker(taskID: batches[index].taskID) { return .failed(blocker) }
        let beforeFailed = batches[index].failedTotal
        let beforeSucceeded = batches[index].succeededTotal
        batches[index].retryPreset = preset
        batches[index].isRetryInFlight = true
        batches[index].status = .sending
        setDelivery(batches[index].taskID, .sending)
        appendRecord(taskID: batches[index].taskID, kind: .retry, at: now,
                     before: "成功 \(beforeSucceeded) · 失败 \(beforeFailed)",
                     after: "确认重试 · \(preset.rawValue)",
                     note: "只处理失败范围，沿用原快照和原分组。取消不会走到这里。")
        return .saved("已确认重试。请推进模拟结束，人数才会变化。")
    }

    func createPendingTask(request: RulePendingTaskRequest, now: Date = Date()) -> ApprovalActionResult {
        if request.expectedReach <= 0 { return .failed("预计人数为 0，不生成空任务。") }
        if let existing = tasks.first(where: { $0.ruleID == request.ruleID && $0.generationCycleKey == request.cycleKey }) {
            return .unchanged("本周期已生成 \(existing.displayName)，没有重复创建。")
        }
        guard audienceRevision(id: request.audienceID, version: request.audienceVersion) != nil else {
            return .failed("规则引用的人群版本不存在。")
        }
        guard request.allocation.groups.allSatisfy({ planRevision(id: $0.planID, version: $0.planVersion) != nil }) else {
            return .failed("规则引用的方案版本不存在。")
        }
        if request.allocation.expectedCounts(total: request.expectedReach).contains(0) {
            return .failed("分组后有 0 人，不生成任务。")
        }
        let assessment = storedAssessment(audienceID: request.audienceID, version: request.audienceVersion)
        guard assessment == .known, reachValue(audienceID: request.audienceID, version: request.audienceVersion) != nil else {
            return .failed("本场景没有可核对的触达范围，不编造人数，也不生成任务。")
        }
        let task = ApprovalTask(
            id: "task-gen-\(recordSerial)", number: allocateNumber(),
            audienceID: request.audienceID, audienceVersion: request.audienceVersion,
            expectedReach: request.expectedReach, allocation: request.allocation,
            approvalStatus: .pending, deliveryStatus: nil, reachState: .known,
            origin: request.origin, originSummary: request.summary,
            isTest: request.allocation.groups.count == 2,
            recommendedAllocation: request.allocation,
            ruleID: request.ruleID, generationCycleKey: request.cycleKey
        )
        tasks.append(task)
        appendRecord(taskID: task.id, kind: .generate, at: now, before: "无",
                     after: "\(task.displayName) · 待审批 · \(request.summary)",
                     note: "规则只生成待审批，没有执行发送。")
        return .saved("已生成 \(task.displayName)。来源：\(request.origin.rawValue)。")
    }

    func simulateAudienceRevision(id: String = "audience-01") -> ApprovalActionResult {
        guard let current = audience(id: id) else { return .failed("人群不存在。") }
        let nextVersion = current.version + 1
        var scores = current.scores
        if let scoreIndex = scores.firstIndex(where: { $0.dimension == .spending }) {
            let increased = min(5, (scores[scoreIndex].value ?? 1) + 1)
            scores[scoreIndex] = AudienceScore(dimension: .spending, value: increased)
        }
        let updated = current.replacing(version: nextVersion, scores: scores)
        archive(updated)
        if let index = audiences.firstIndex(where: { $0.id == id }) { audiences[index] = updated }
        let oldScore = current.scores.first { $0.dimension == .spending }?.displayValue ?? "—"
        let newScore = updated.scores.first { $0.dimension == .spending }?.displayValue ?? "—"
        revisionNotes[revisionKey(id, nextVersion)] = "消费水平 \(oldScore) → \(newScore)"
        if let oldReach = reachFixtures[revisionKey(id, current.version)], oldReach > 0 {
            reachFixtures[revisionKey(id, nextVersion)] = max(20, oldReach - 200)
        }
        return .saved("\(updated.displayName) 当前为 V\(nextVersion)。已有任务仍引用旧版本。")
    }

    func simulatePlanRevision(id: String = "plan-01") -> ApprovalActionResult {
        guard let current = plan(id: id) else { return .failed("方案不存在。") }
        let nextVersion = current.version + 1
        let message = "这是 \(current.displayName) V\(nextVersion) 的演示话术，只用于版本核对，不会真实发送。"
        let updated = current.replacing(version: nextVersion, message: message)
        archive(updated)
        if let index = plans.firstIndex(where: { $0.id == id }) { plans[index] = updated }
        revisionNotes[revisionKey(id, nextVersion)] = "话术更新为 V\(nextVersion) 演示文本"
        return .saved("\(updated.displayName) 当前为 V\(nextVersion)。已有任务仍引用旧版本。")
    }

    func setResourceInvalid(planID: String, invalid: Bool) -> ApprovalActionResult {
        guard let plan = plan(id: planID) else { return .failed("方案不存在。") }
        resourceValid[planID] = !invalid
        if invalid {
            resourceReasons[planID] = "\(plan.displayName) 的示例资源在参考日 2026/10/11 已失效。"
            return .saved("\(plan.displayName) 已标为资源失效。确认和重试都会被阻止。")
        }
        resourceReasons[planID] = nil
        return .saved("\(plan.displayName) 资源已恢复有效。")
    }

    func removePinnedAudienceSnapshot(taskID: String = "task-01") -> ApprovalActionResult {
        guard let task = task(id: taskID) else { return .failed("任务不存在。") }
        guard let current = audience(id: task.audienceID) else { return .failed("人群已不可用。") }
        guard current.version != task.audienceVersion else {
            return .failed("任务还在引用当前版本。请先模拟发布新版本，再移除旧快照。")
        }
        let key = revisionKey(task.audienceID, task.audienceVersion)
        guard audienceRevisions[key] != nil else { return .unchanged("旧快照已经不存在。") }
        audienceRevisions.removeValue(forKey: key)
        return .saved("已移除旧人群快照。继续原版本会被阻止。")
    }

    func breakAudienceReference(taskID: String = "task-01", now: Date = Date()) -> ApprovalActionResult {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return .failed("任务不存在。") }
        guard tasks[index].approvalStatus == .pending || tasks[index].approvalStatus == .deferred else {
            return .failed("已确认或已拒绝的任务不能改引用。")
        }
        let before = tasks[index].audienceID
        tasks[index].audienceID = "audience-missing"
        tasks[index].reachState = .unavailable
        appendRecord(taskID: taskID, kind: .changeAudience, at: now, before: before, after: "audience-missing",
                     note: "演示缺失引用。不会自动改选其他人群。")
        return .saved("任务 01 的人群引用已断开。")
    }

    func createSinglePlanSample(now: Date = Date()) -> ApprovalActionResult {
        guard let audience = audience(id: "audience-01"), let plan = plan(id: "plan-01") else {
            return .failed("缺少人群 01 或方案 01。")
        }
        guard let reach = reachValue(audienceID: audience.id, version: audience.version) else {
            return .failed("人群 01 当前版本没有可核对人数。")
        }
        guard let allocation = ABAllocation(groups: [.init(planID: plan.id, planVersion: plan.version, percentage: 100)]) else {
            return .failed("单方案分配无效。")
        }
        let task = ApprovalTask(
            id: "task-single-\(recordSerial)", number: allocateNumber(),
            audienceID: audience.id, audienceVersion: audience.version,
            expectedReach: reach, allocation: allocation,
            approvalStatus: .pending, deliveryStatus: nil,
            origin: .manualTest, originSummary: "手动测试 · 单方案 100%",
            isTest: false, recommendedAllocation: allocation
        )
        tasks.append(task)
        appendRecord(taskID: task.id, kind: .generate, at: now, before: "无",
                     after: "\(task.displayName) · 单方案 100%", note: "演示样本。")
        return .saved("已生成单方案任务 \(task.displayName)。")
    }

    func prepareStatusSamples(now: Date = Date()) -> ApprovalActionResult {
        guard let audience = audienceRevision(id: "audience-01", version: 1),
              let planA = planRevision(id: "plan-01", version: 1),
              let planB = planRevision(id: "plan-02", version: 1),
              let allocation = ABAllocation(groups: [
                .init(planID: planA.id, planVersion: 1, percentage: 30),
                .init(planID: planB.id, planVersion: 1, percentage: 70)
              ]) else { return .failed("缺少 V1 样本，无法准备五种状态。") }
        let specs: [(String, DeliveryStatus, DeliveryPreset)] = [
            ("task-demo-waiting", .waiting, .succeeded),
            ("task-demo-sending", .sending, .succeeded),
            ("task-demo-succeeded", .succeeded, .succeeded),
            ("task-demo-partial", .partiallyFailed, .partiallyFailed),
            ("task-demo-failed", .failed, .failed)
        ]
        var created = 0
        for spec in specs where task(id: spec.0) == nil {
            let task = ApprovalTask(
                id: spec.0, number: allocateNumber(),
                audienceID: audience.id, audienceVersion: 1, expectedReach: 2_000,
                allocation: allocation, approvalStatus: .confirmed, deliveryStatus: spec.1,
                origin: .manualTest, originSummary: "演示状态样本 · \(spec.1.rawValue)",
                isTest: true, recommendedAllocation: allocation
            )
            guard var snapshot = makeSnapshot(task: task, batchID: "batch-\(spec.0)", at: now) else { continue }
            snapshot = DeliverySnapshot(
                id: snapshot.id, taskID: snapshot.taskID, batchID: snapshot.batchID,
                confirmedAt: now, businessDate: Self.referenceDate, origin: snapshot.origin,
                originSummary: snapshot.originSummary, audienceID: snapshot.audienceID,
                audienceNumber: snapshot.audienceNumber, audienceVersion: snapshot.audienceVersion,
                memberCount: snapshot.memberCount, scores: snapshot.scores, expectedReach: snapshot.expectedReach,
                dedupNote: snapshot.dedupNote, groups: snapshot.groups
            )
            var batch = DeliveryBatch(
                id: snapshot.batchID, taskID: task.id, snapshotID: snapshot.id, businessDate: Self.referenceDate,
                status: .waiting,
                groups: snapshot.groups.map { GroupDeliveryCount(planID: $0.planID, allocated: $0.allocatedCount, succeeded: 0, failed: 0) },
                retryCount: 0, failureReason: nil, startedAt: spec.1 == .waiting ? nil : now, finishedAt: nil,
                preset: spec.2, retryPreset: .allSucceeded, isRetryInFlight: false, statisticsStatus: .collecting
            )
            switch spec.1 {
            case .waiting:
                break
            case .sending:
                batch.status = .sending
            case .succeeded, .partiallyFailed, .failed:
                batch.applyInitialPreset(now: now)
            }
            tasks.append(task)
            snapshots.append(snapshot)
            batches.append(batch)
            appendRecord(taskID: task.id, kind: .generate, at: now, before: "无",
                         after: "\(task.displayName) · \(spec.1.rawValue)", note: "五种状态演示样本，成交为统计中。")
            created += 1
        }
        if created == 0 { return .unchanged("五种状态样本都已存在，没有重复创建。") }
        return .saved("已补齐 \(created) 条发送状态样本。历史统计没有改动。")
    }

    func rejectAllPending(now: Date = Date()) -> ApprovalActionResult {
        let ids = tasks.filter { $0.approvalStatus == .pending || $0.approvalStatus == .deferred }.map(\.id)
        if ids.isEmpty { return .unchanged("当前没有待审批任务。") }
        for id in ids {
            _ = rejectTask(taskID: id, reason: "演示空列表", now: now)
        }
        return .saved("已拒绝 \(ids.count) 条待审批任务。可在处理记录中查看。")
    }

    private func verifyRuleGate() -> [String] {
        guard let allocation = ABAllocation(groups: [
            .init(planID: "plan-01", planVersion: 1, percentage: 30),
            .init(planID: "plan-02", planVersion: 1, percentage: 70)
        ]) else { return ["规则探针分配无效"] }
        let request = RulePendingTaskRequest(
            ruleID: "rule-probe", cycleKey: "2026-10-11", origin: .birthdayRule,
            summary: "探针", audienceID: "audience-01", audienceVersion: 1,
            expectedReach: 2_000, allocation: allocation
        )
        var errors: [String] = []
        if case .saved = createPendingTask(request: request) {} else { errors.append("首次规则生成应成功") }
        if case .unchanged = createPendingTask(request: request) {} else { errors.append("同周期不应重复生成") }
        let empty = RulePendingTaskRequest(
            ruleID: "rule-empty", cycleKey: "2026-10-11", origin: .birthdayRule,
            summary: "空", audienceID: "audience-01", audienceVersion: 1,
            expectedReach: 0, allocation: allocation
        )
        if case .failed = createPendingTask(request: empty) {} else { errors.append("0 人不应生成任务") }
        return errors
    }

    private func load(_ seed: MockDataStore) {
        audiences = seed.audiences + Self.extraAudiences
        plans = seed.plans
        analytics = seed.analytics
        audienceRevisions = [:]
        planRevisions = [:]
        revisionNotes = [:]
        resourceValid = [:]
        resourceReasons = [:]
        audiences.forEach { archive($0) }
        plans.forEach {
            archive($0)
            resourceValid[$0.id] = true
        }
        reachFixtures = [
            "audience-01#1": 2_000,
            "audience-02#1": 900,
            "audience-03#1": 0,
            "audience-04#1": 400,
            "audience-05#1": 50
        ]
        tasks = seed.approvalTasks.map { task in
            ApprovalTask(
                id: task.id, number: task.number, audienceID: task.audienceID,
                audienceVersion: task.audienceVersion, expectedReach: task.expectedReach,
                allocation: task.allocation, approvalStatus: task.approvalStatus,
                deliveryStatus: task.deliveryStatus,
                origin: .aiRecommendation,
                originSummary: task.id == "task-history-01" ? "AI 推荐 · 历史已发送样本" : "AI 推荐比例 30%／70%",
                isTest: true, recommendedAllocation: task.allocation
            )
        }
        records = []
        snapshots = []
        batches = []
        numberCursor = 3
        recordSerial = 1
        let generatedAt = Self.referenceDate.addingTimeInterval(8 * 3_600)
        if task(id: "task-01") != nil {
            appendRecord(taskID: "task-01", kind: .generate, at: generatedAt, before: "无",
                         after: "任务 01 · 待审批 · 人群 01 · 2,000 人 · 30%／70%",
                         note: "初始样本。", operatorName: ApprovalExecutionMath.operatorName)
        }
        if let history = task(id: "task-history-01"),
           let snapshot = makeSnapshot(task: history, batchID: "batch-history-01", at: generatedAt.addingTimeInterval(3_600)) {
            let confirmedAt = generatedAt.addingTimeInterval(3_600)
            let finishedAt = confirmedAt.addingTimeInterval(300)
            snapshots.append(snapshot)
            batches.append(DeliveryBatch(
                id: "batch-history-01", taskID: history.id, snapshotID: snapshot.id,
                businessDate: Self.referenceDate, status: .succeeded,
                groups: [
                    GroupDeliveryCount(planID: "plan-01", allocated: 600, succeeded: 600, failed: 0),
                    GroupDeliveryCount(planID: "plan-02", allocated: 1_400, succeeded: 1_400, failed: 0)
                ],
                retryCount: 0, failureReason: nil, startedAt: confirmedAt, finishedAt: finishedAt,
                preset: .succeeded, retryPreset: .allSucceeded, isRetryInFlight: false,
                statisticsStatus: .historicalSample
            ))
            appendRecord(taskID: history.id, kind: .confirm, at: confirmedAt, before: "待审批",
                         after: "已确认 · 等待发送 · batch-history-01", note: "历史样本，已固定。")
            appendRecord(taskID: history.id, kind: .simulationFinish, at: finishedAt, before: "发送中",
                         after: "发送成功 · 成功 2000 · 失败 0", note: "历史成交在数据页，不在这条任务里重写。")
        }
    }

    private func makeSnapshot(task: ApprovalTask, batchID: String, at: Date) -> DeliverySnapshot? {
        guard let audience = audienceRevision(id: task.audienceID, version: task.audienceVersion) else { return nil }
        let counts = task.allocation.expectedCounts(total: task.expectedReach)
        guard counts.count == task.allocation.groups.count else { return nil }
        var groups: [DeliverySnapshot.Group] = []
        for (index, group) in task.allocation.groups.enumerated() {
            guard let plan = planRevision(id: group.planID, version: group.planVersion) else { return nil }
            groups.append(.init(
                planID: plan.id, planVersion: plan.version, planNumber: plan.number,
                purpose: plan.purpose, customerStage: plan.customerStage, message: plan.message,
                resourceSummary: plan.resourceSummary, resourceWasValid: isResourceValid(planID: plan.id),
                percentage: group.percentage, allocatedCount: counts[index]
            ))
        }
        return DeliverySnapshot(
            id: "snapshot-\(task.id)", taskID: task.id, batchID: batchID, confirmedAt: at,
            businessDate: Self.referenceDate, origin: task.origin, originSummary: task.originSummary,
            audienceID: audience.id, audienceNumber: audience.number, audienceVersion: audience.version,
            memberCount: audience.memberCount, scores: audience.scores, expectedReach: task.expectedReach,
            dedupNote: ApprovalExecutionMath.dedupNote, groups: groups
        )
    }

    private func writeReach(index: Int, audienceID: String, version: Int) {
        switch reachAssessment(audienceID: audienceID, version: version) {
        case .known:
            tasks[index].expectedReach = reachFixtures[revisionKey(audienceID, version)] ?? 0
            tasks[index].reachState = .known
        case .pendingReview:
            tasks[index].reachState = .pendingReview
        case .zeroCoverage:
            tasks[index].expectedReach = 0
            tasks[index].reachState = .zeroCoverage
        case .unavailable:
            tasks[index].reachState = .unavailable
        }
    }

    private func storedAssessment(audienceID: String, version: Int) -> TaskReachState {
        reachAssessment(audienceID: audienceID, version: version)
    }

    private func setDelivery(_ taskID: String, _ status: DeliveryStatus) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].deliveryStatus = status
    }

    private func resourceBlocker(taskID: String) -> String? {
        let planIDs = snapshot(for: taskID)?.groups.map(\.planID) ?? task(id: taskID)?.allocation.groups.map(\.planID) ?? []
        for planID in planIDs where !isResourceValid(planID: planID) {
            let name = plan(id: planID)?.displayName ?? "方案"
            return "\(name) 资源已失效，不能继续发送。请先到方案模块处理。"
        }
        return nil
    }

    private func appendRecord(
        taskID: String, kind: ApprovalRecordKind, at: Date, before: String, after: String,
        note: String, operatorName: String = ApprovalExecutionMath.operatorName
    ) {
        records.append(ApprovalRecord(
            id: "record-\(recordSerial)", serial: recordSerial, taskID: taskID, kind: kind, at: at,
            beforeSummary: before, afterSummary: after, note: note, operatorName: operatorName
        ))
        recordSerial += 1
    }

    private func allocateNumber() -> Int {
        while tasks.contains(where: { $0.number == numberCursor }) { numberCursor += 1 }
        let number = numberCursor
        numberCursor += 1
        return number
    }

    private func archive(_ audience: Audience) {
        audienceRevisions[revisionKey(audience.id, audience.version)] = audience
    }

    private func archive(_ plan: MarketingPlan) {
        planRevisions[revisionKey(plan.id, plan.version)] = plan
    }

    private func revisionKey(_ id: String, _ version: Int) -> String { "\(id)#\(version)" }

    private func audienceText(id: String, version: Int, reach: Int, state: TaskReachState) -> String {
        let name = audienceRevision(id: id, version: version)?.displayName ?? "人群不可用"
        let reachText = state == .known ? "\(reach) 人" : state.rawValue
        return "\(name) V\(version) · \(reachText)"
    }

    private func planText(_ allocation: ABAllocation) -> String {
        allocation.groups.enumerated().map { index, group in
            let name = planRevision(id: group.planID, version: group.planVersion)?.displayName ?? "方案不可用"
            let label = index == 0 ? "A" : "B"
            return "\(label) \(name) V\(group.planVersion)"
        }.joined(separator: "，")
    }

    private func percentTextSummary(_ allocation: ABAllocation, reach: Int, state: TaskReachState) -> String {
        let counts = state == .known ? allocation.expectedCounts(total: reach) : []
        return allocation.groups.enumerated().map { index, group in
            let count = counts.indices.contains(index) ? " / \(counts[index]) 人" : ""
            return "\(group.percentage)%\(count)"
        }.joined(separator: "，")
    }

    private static let extraAudiences: [Audience] = [
        Audience(
            id: "audience-03", number: 3, memberCount: 0, source: .manual, version: 1,
            scores: AudienceScore.Dimension.allCases.map { AudienceScore(dimension: $0, value: 3) },
            categoryPreferences: [CategoryPreference(id: "category-a", name: "品类 A", percentage: 100)]
        ),
        Audience(
            id: "audience-04", number: 4, memberCount: 1_200, source: .manual, version: 1,
            scores: [
                AudienceScore(dimension: .spending, value: 3),
                AudienceScore(dimension: .frequency, value: nil),
                AudienceScore(dimension: .priceSensitivity, value: 3),
                AudienceScore(dimension: .newProducts, value: 3),
                AudienceScore(dimension: .classics, value: 3)
            ],
            categoryPreferences: [CategoryPreference(id: "category-a", name: "品类 A", percentage: 100)]
        ),
        Audience(
            id: "audience-05", number: 5, memberCount: 80, source: .manual, version: 1,
            scores: AudienceScore.Dimension.allCases.map { AudienceScore(dimension: $0, value: 3) },
            categoryPreferences: [CategoryPreference(id: "category-a", name: "品类 A", percentage: 100)]
        )
    ]
}
