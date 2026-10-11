import Foundation
import Observation

@MainActor
@Observable
final class DemoSession {
    private let seed: MockDataStore
    private(set) var audienceSnapshots: [AudienceSnapshot] = []
    private(set) var plans: [MarketingPlan] = []
    private(set) var approvalTasks: [ApprovalTask] = []
    private(set) var analytics: AnalyticsSummary
    private(set) var fields: [AudienceField] = []
    private(set) var versions: [VersionRecord] = []
    private(set) var suggestions: [DemoSuggestion] = []
    private(set) var resetGeneration = 0
    private var nextAudienceNumber = 1

    // Approval execution and B metadata live in the same observed session.
    private(set) var records: [ApprovalRecord] = []
    private(set) var snapshots: [DeliverySnapshot] = []
    private(set) var batches: [DeliveryBatch] = []
    private(set) var analyticsStatistics = AnalyticsBatchStatistics()
    private var revisionNotes: [String: String] = [:]
    private var reachFixtures: [String: Int] = [:]
    private var resourceValid: [String: Bool] = [:]
    private var resourceReasons: [String: String] = [:]
    private var unavailableApprovalVersions: Set<String> = []
    private var numberCursor = 3
    private var recordSerial = 1
    private(set) var planMetadata: [String: PlanMetadata] = [:]
    private(set) var planVersions: [PlanVersionSnapshot] = []
    private(set) var planSuggestions: [PlanSuggestion] = []
    private(set) var touchRules: [TouchRule] = []
    private(set) var ruleGenerations: [PlanRuleGeneration] = []
    static let referenceDate = MockDataStore.planReferenceDate


    init(store: MockDataStore = .demo) {
        seed = store
        analytics = store.analytics
        restoreSeed()
    }
    var audiences: [Audience] { audienceSnapshots.map(\.audience) }
    var store: MockDataStore { .init(audiences: audiences, plans: plans, approvalTasks: approvalTasks, analytics: analytics) }
    /// The existing read-only approval UI must display the referenced profile, never current V2 as V1.
    var approvalStore: MockDataStore {
        let frozen: [Audience] = audiences.compactMap { current in
            guard let task = approvalTasks.first(where: { $0.audienceID == current.id }) else { return current }
            return audienceVersion(id: current.id, version: task.audienceVersion)?.audience
        }
        let frozenPlans: [MarketingPlan] = plans.compactMap { current in
            guard let group = approvalTasks.flatMap({ $0.allocation.groups }).first(where: { $0.planID == current.id }) else { return current }
            return planVersion(id: current.id, version: group.planVersion)
        }
        return .init(audiences: frozen, plans: frozenPlans, approvalTasks: approvalTasks, analytics: analytics)
    }
    func audience(id: String) -> AudienceSnapshot? { audienceSnapshots.first { $0.audience.id == id } }
    func audienceVersion(id: String, version: Int) -> AudienceSnapshot? {
        guard let record = versions.first(where: { $0.objectKind == .audience && $0.objectID == id && $0.version == version }),
              case .audience(let snapshot) = record.content else { return nil }
        return snapshot
    }
    func planVersion(id: String, version: Int) -> MarketingPlan? {
        guard let record = versions.first(where: { $0.objectKind == .plan && $0.objectID == id && $0.version == version }),
              case .plan(let plan) = record.content else { return nil }
        return plan
    }
    func history(kind: VersionObjectKind, id: String) -> [VersionRecord] {
        versions.filter { $0.objectKind == kind && $0.objectID == id }.sorted { $0.version > $1.version }
    }
    func coverage(for selection: [Audience]) -> Int? {
        if selection.isEmpty { return 0 }
        let snapshots = selection.compactMap { audience(id: $0.id) }
        guard snapshots.count == selection.count,
              snapshots.allSatisfy({ $0.recognition == .ready || $0.recognition == .empty }) else { return nil }
        if selection.count == 1 { return selection[0].memberCount }
        if Set(selection.map(\.id)) == Set(["audience-01", "audience-02"]),
           selection.allSatisfy({ current in MockDataStore.demo.audience(id: current.id) == current }) {
            return MockDataStore.audienceUnionCoverage
        }
        return nil
    }
    func reset() { restoreSeed(); resetGeneration += 1 }
    private func restoreSeed() {
        plans = seed.plans; approvalTasks = seed.approvalTasks; analytics = seed.analytics
        fields = MockDataStore.audienceFields
        suggestions = MockDataStore.audienceSuggestions.filter { suggestion in seed.audience(id: suggestion.targetID) != nil }
        audienceSnapshots = seed.audiences.map {
            .init(audience: $0, rules: MockDataStore.audienceRules(number: $0.number), recognition: .ready, metadata: .demo)
        }
        versions = audienceSnapshots.map { versionRecord($0, source: .seed, summary: "初始规则及画像固定样本", at: DemoClock.referenceDate) }
        versions += plans.map {
            .init(id: "plan:\($0.id):\($0.version)", objectKind: .plan, objectID: $0.id, version: $0.version,
                  createdAt: DemoClock.referenceDate, changeSource: .seed, summary: "初始方案固定样本", content: .plan($0))
        }
        nextAudienceNumber = (seed.audiences.map(\.number).max() ?? 0) + 1
        restorePlanSeed()
        restoreApprovalSeed()
        analyticsStatistics.reset()
    }
    private func versionRecord(_ snapshot: AudienceSnapshot, source: VersionChangeSource, summary: String, at: Date) -> VersionRecord {
        .init(id: "audience:\(snapshot.audience.id):\(snapshot.audience.version)", objectKind: .audience,
              objectID: snapshot.audience.id, version: snapshot.audience.version, createdAt: at,
              changeSource: source, summary: summary, content: .audience(snapshot))
    }
    private func validate(_ rules: AudienceRules, existing: AudienceRules?) throws {
        guard !rules.conditions.isEmpty else { throw DemoValidationError(message: "至少添加一条有效条件。") }
        guard Set(rules.conditions.map(\.id)).count == rules.conditions.count else { throw DemoValidationError(message: "条件 ID 重复，请重新添加条件。") }
        guard Set(rules.conditions.map { $0.field.id }).count == rules.conditions.count else { throw DemoValidationError(message: "同一字段有重复或冲突条件，请合并为一个区间。") }
        for condition in rules.conditions {
            guard let current = fields.first(where: { $0.id == condition.field.id }) else { throw DemoValidationError(message: "字段已不可用。") }
            // An unchanged existing condition can retain its frozen field definition, even if disabled.
            if existing?.conditions.contains(condition) == true { continue }
            guard current.isEnabled else { throw DemoValidationError(message: "\(current.name)已停用，不能用于新条件。") }
            guard condition.field == current else { throw DemoValidationError(message: "\(current.name)定义已更新，请重新选择字段。") }
            guard AudienceRuleOperator.allowed(for: current.type).contains(condition.operation) else { throw DemoValidationError(message: "\(current.name)的判断方式与字段类型不匹配。") }
            switch (current.type, condition.value) {
            case (.number, .number(let value)):
                guard value.isFinite, value >= 0, condition.operation != .between else { throw DemoValidationError(message: "请输入有效的非负数字；区间需要上下限。") }
            case (.number, .range(let lower, let upper)):
                guard condition.operation == .between, lower.isFinite, upper.isFinite, lower >= 0, lower <= upper else { throw DemoValidationError(message: "区间下限不能大于上限，且必须是有效非负数字。") }
            case (.category, .category(let value)):
                guard current.options.contains(value), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DemoValidationError(message: "请选择有效分类属性值。") }
            case (.date, .date(let date)):
                guard date.timeIntervalSince1970.isFinite else { throw DemoValidationError(message: "日期无效。") }
            case (.boolean, .boolean): break
            default: throw DemoValidationError(message: "\(current.name)的属性值与字段类型不匹配。")
            }
        }
    }
    @discardableResult
    func saveAudience(id: String?, baseVersion: Int?, rules: AudienceRules, source: VersionChangeSource = .manualEdit) throws -> AudienceSnapshot {
        let existing = id.flatMap { audience(id: $0) }
        if id != nil && existing == nil { throw DemoValidationError(message: "人群不存在，请返回列表。") }
        if let existing, existing.audience.version != baseVersion { throw DemoValidationError(message: "人群版本已变化，请重新打开编辑。") }
        var clean = rules
        clean.instruction = rules.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.conditions = clean.conditions.map { condition in
            guard case .date(let date) = condition.value else { return condition }
            return AudienceRuleCondition(id: condition.id, field: condition.field, operation: condition.operation,
                                         value: .date(DemoClock.calendar.startOfDay(for: date)))
        }
        try validate(clean, existing: existing?.rules)
        if let existing, existing.rules == clean { return existing }
        let number = existing?.audience.number ?? nextAudienceNumber
        let new = Audience(id: existing?.audience.id ?? UUID().uuidString, number: number, memberCount: 0,
                           source: existing?.audience.source ?? .manual, version: (existing?.audience.version ?? 0) + 1,
                           scores: AudienceScore.Dimension.allCases.map { .init(dimension: $0, value: nil) }, categoryPreferences: [])
        var metadata = AudienceProfileMetadata.demo
        metadata.updatedAt = Date()
        let snapshot = AudienceSnapshot(audience: new, rules: clean, recognition: .recognizing, metadata: metadata)
        if let index = audienceSnapshots.firstIndex(where: { $0.audience.id == new.id }) { audienceSnapshots[index] = snapshot }
        else { audienceSnapshots.append(snapshot); nextAudienceNumber += 1 }
        let summary: String
        if let existing {
            summary = "\(existing.rules.conditions.map(\.summary).joined(separator: "；")) → \(clean.conditions.map(\.summary).joined(separator: "；"))；\(clean.relation.rawValue)；说明\(existing.rules.instruction == clean.instruction ? "未变" : "已更新")"
        } else { summary = "创建规则：\(clean.conditions.map(\.summary).joined(separator: "；"))" }
        versions.append(versionRecord(snapshot, source: source, summary: summary, at: Date()))
        return snapshot
    }
    func completeRecognition(id: String, version: Int, scenario: AudienceRecognition) throws {
        guard scenario != .recognizing,
              let index = audienceSnapshots.firstIndex(where: { $0.audience.id == id }),
              audienceSnapshots[index].audience.version == version else { throw DemoValidationError(message: "人群版本已变化或识别场景无效。") }
        var snapshot = audienceSnapshots[index]
        // Each version completes once; a refresh doesn't rewrite already frozen historical results.
        guard snapshot.recognition == .recognizing else { throw DemoValidationError(message: "本版本模拟识别已完成，请编辑规则后再选择场景。") }
        guard let template = seed.audiences.first else { throw DemoValidationError(message: "没有可用的模拟画像样本。") }
        let old = snapshot.audience
        snapshot.audience = Audience(id: old.id, number: old.number, memberCount: scenario == .ready ? template.memberCount : 0,
                                     source: old.source, version: old.version,
                                     scores: scenario == .ready ? template.scores : AudienceScore.Dimension.allCases.map { .init(dimension: $0, value: nil) },
                                     categoryPreferences: scenario == .ready ? template.categoryPreferences : [])
        snapshot.recognition = scenario; snapshot.metadata.updatedAt = Date()
        audienceSnapshots[index] = snapshot
        if let record = versions.firstIndex(where: { $0.objectKind == .audience && $0.objectID == id && $0.version == version }) {
            versions[record].content = .audience(snapshot)
        }
    }
    @discardableResult
    func saveField(_ draft: AudienceField) throws -> AudienceField {
        let existing = fields.first { $0.id == draft.id }
        if let existing, existing.version != draft.version { throw DemoValidationError(message: "字段版本已变化，请重新打开编辑。") }
        guard !draft.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.isBuiltIn == (existing?.isBuiltIn ?? false) else { throw DemoValidationError(message: "字段标识或内置属性无效。") }
        var clean = draft
        clean.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.explanation = draft.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.evidence = draft.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.options = draft.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !clean.name.isEmpty, !clean.explanation.isEmpty, !clean.evidence.isEmpty else { throw DemoValidationError(message: "字段名称、说明和识别依据不能为空。") }
        guard !fields.contains(where: { $0.id != clean.id && $0.name.caseInsensitiveCompare(clean.name) == .orderedSame }) else { throw DemoValidationError(message: "字段名称重复，请使用不同名称。") }
        if clean.type == .category {
            guard !clean.options.isEmpty, clean.options.allSatisfy({ !$0.isEmpty }), Set(clean.options.map { $0.lowercased() }).count == clean.options.count else { throw DemoValidationError(message: "分类属性值不能为空或重复，至少保留一个。") }
        } else { clean.options = [] }
        if let existing, existing.isBuiltIn {
            guard clean.name == existing.name, clean.type == existing.type, clean.explanation == existing.explanation, clean.options == existing.options, clean.evidence == existing.evidence else { throw DemoValidationError(message: "内置字段语义不可修改。") }
        }
        if existing == clean { return clean }
        clean.version = (existing?.version ?? 0) + 1
        if let index = fields.firstIndex(where: { $0.id == clean.id }) { fields[index] = clean } else { fields.append(clean) }
        return clean
    }
    @discardableResult
    func adoptSuggestion(id: String) throws -> AudienceSnapshot {
        guard let index = suggestions.firstIndex(where: { $0.id == id }) else { throw DemoValidationError(message: "建议不存在。") }
        let suggestion = suggestions[index]
        guard suggestion.status == .pending || suggestion.status == .deferred else { throw DemoValidationError(message: "该建议已采纳或已失效，不能重复采纳。") }
        guard suggestion.targetKind == .audience, let current = audience(id: suggestion.targetID), current.audience.version == suggestion.baseVersion else { throw DemoValidationError(message: "建议基于旧版本，请重新核对，不能覆盖最新版。") }
        guard let rules = suggestion.proposedRules, rules != current.rules else { throw DemoValidationError(message: "建议没有可保存的规则变更。") }
        let result = try saveAudience(id: suggestion.targetID, baseVersion: suggestion.baseVersion, rules: rules, source: .aiAdoption)
        suggestions[index].status = .adopted; suggestions[index].generatedVersion = result.audience.version; suggestions[index].processedAt = Date()
        return result
    }
    func deferSuggestion(id: String) throws {
        guard let index = suggestions.firstIndex(where: { $0.id == id }), suggestions[index].status == .pending else { throw DemoValidationError(message: "只有待处理建议可以暂不采纳。") }
        suggestions[index].status = .deferred; suggestions[index].processedAt = Date()
    }
    /// B's minimal write contract; feature-specific resource validation belongs to B's future integration.
    func savePlan(_ plan: MarketingPlan, baseVersion: Int) throws {
        guard let index = plans.firstIndex(where: { $0.id == plan.id }), plans[index].version == baseVersion,
              plan.number == plans[index].number, plan.version == baseVersion + 1,
              !plan.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              plan.audienceIDs.allSatisfy({ audience(id: $0) != nil }) else { throw DemoValidationError(message: "方案版本、编号、话术或人群引用无效。") }
        plans[index] = plan
        versions.append(.init(id: "plan:\(plan.id):\(plan.version)", objectKind: .plan, objectID: plan.id, version: plan.version,
                              createdAt: Date(), changeSource: .manualEdit, summary: "方案内容保存", content: .plan(plan)))
        recordPlanSnapshot(plan, source: .manual, summary: "方案内容保存")
    }
    /// C's draft-only write contract. Confirmed/history tasks cannot be rewritten through this method.
    func updatePendingTask(_ task: ApprovalTask) throws {
        guard let index = approvalTasks.firstIndex(where: { $0.id == task.id }),
              [.pending, .deferred].contains(approvalTasks[index].approvalStatus),
              [.pending, .deferred, .rejected].contains(task.approvalStatus), task.deliveryStatus == nil,
              task.number == approvalTasks[index].number, task.expectedReach >= 0,
              let snapshot = audienceVersion(id: task.audienceID, version: task.audienceVersion),
              snapshot.recognition == .ready, task.expectedReach <= snapshot.audience.memberCount,
              task.allocation.groups.allSatisfy({ planVersion(id: $0.planID, version: $0.planVersion) != nil }) else { throw DemoValidationError(message: "任务状态、版本引用或覆盖人数无效。") }
        approvalTasks[index] = task
    }
}

// C actions operate on the same session and frozen A/B versions.
extension DemoSession {
    func task(id: String) -> ApprovalTask? { tasks.first { $0.id == id } }
    func approvalAudience(id: String) -> Audience? { approvalAudiences.first { $0.id == id } }
    func plan(id: String) -> MarketingPlan? { plans.first { $0.id == id } }
    func audienceRevision(id: String, version: Int) -> Audience? {
        guard !unavailableApprovalVersions.contains(revisionKey(id, version)) else { return nil }
        return audienceVersion(id: id, version: version)?.audience
            ?? Self.extraAudiences.first { $0.id == id && $0.version == version }
    }
    func planRevision(id: String, version: Int) -> MarketingPlan? { planVersion(id: id, version: version) }
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

    func adjustmentReach(taskID: String, audienceID: String, version: Int) -> Int? {
        if let current = task(id: taskID), current.ruleID != nil,
           current.audienceID == audienceID, current.audienceVersion == version,
           current.reachState == .known { return current.expectedReach }
        return knownReach(audienceID: audienceID, version: version)
    }

    func reachAssessment(audienceID: String, version: Int) -> TaskReachState {
        guard let audience = audienceRevision(id: audienceID, version: version) else { return .unavailable }
        if let state = audienceVersion(id: audienceID, version: version)?.recognition,
           state == .recognizing || state == .insufficient { return .pendingReview }
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

    func isResourceValid(planID: String, version: Int? = nil) -> Bool {
        guard resourceValid[planID] != false, plan(id: planID) != nil else { return false }
        let resourceID: String?
        if let version {
            guard let frozen = planVersions.first(where: { $0.plan.id == planID && $0.plan.version == version }) else { return false }
            resourceID = frozen.metadata.resourceID
        } else { resourceID = planMetadata[planID]?.resourceID }
        guard let resourceID else { return true }
        return storeResources.first { $0.id == resourceID }?.invalidReason(on: Self.referenceDate) == nil
            && storeResources.contains { $0.id == resourceID }
    }

    func resourceInvalidReason(planID: String) -> String? {
        guard !isResourceValid(planID: planID) else { return nil }
        return resourceReasons[planID] ?? "资源已失效。请到方案模块替换或选择可用版本。"
    }

    func versionDifferences(for task: ApprovalTask) -> [String] {
        var lines: [String] = []
        if let current = approvalAudience(id: task.audienceID), current.version != task.audienceVersion {
            let note = revisionNotes[revisionKey(task.audienceID, current.version)] ?? "内容已更新"
            lines.append("\(current.displayName)：任务使用 V\(task.audienceVersion)，当前是 V\(current.version)。\(note)")
        } else if approvalAudience(id: task.audienceID) == nil {
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
        if let audience = audienceRevision(id: task.audienceID, version: task.audienceVersion),
           task.expectedReach > audience.memberCount {
            issues.append("本次触达不能超过该版本人群覆盖。")
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
            if !isResourceValid(planID: group.planID, version: group.planVersion) {
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
        let reach = adjustmentReach(taskID: taskID, audienceID: audienceID, version: audienceVersion)
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
        if audienceChanged || task.ruleID == nil {
            writeReach(index: index, audienceID: audienceID, version: audienceVersion)
        }
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
        if let current = approvalAudience(id: task.audienceID), current.version != task.audienceVersion {
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
        if audienceChanged || tasks[index].ruleID == nil {
            writeReach(index: index, audienceID: tasks[index].audienceID, version: tasks[index].audienceVersion)
        }
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
        syncAnalytics(batchID: batch.id)
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
            syncAnalytics(batchID: batch.id)
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
        guard let audience = audienceRevision(id: request.audienceID, version: request.audienceVersion) else {
            return .failed("规则引用的人群版本不存在。")
        }
        guard request.expectedReach <= audience.memberCount,
              request.expectedReach <= (reachValue(audienceID: request.audienceID, version: request.audienceVersion) ?? 0) else {
            return .failed("规则触达超过已核对范围。")
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
        guard let current = approvalAudience(id: id) else { return .failed("人群不存在。") }
        let nextVersion = current.version + 1
        var scores = current.scores
        if let scoreIndex = scores.firstIndex(where: { $0.dimension == .spending }) {
            let increased = min(5, (scores[scoreIndex].value ?? 1) + 1)
            scores[scoreIndex] = AudienceScore(dimension: .spending, value: increased)
        }
        let updated = current.replacing(version: nextVersion, scores: scores)
        archive(updated)

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
        guard let current = approvalAudience(id: task.audienceID) else { return .failed("人群已不可用。") }
        guard current.version != task.audienceVersion else {
            return .failed("任务还在引用当前版本。请先模拟发布新版本，再移除旧快照。")
        }
        let key = revisionKey(task.audienceID, task.audienceVersion)
        guard audienceRevision(id: task.audienceID, version: task.audienceVersion) != nil else { return .unchanged("旧快照已经不存在。") }
        unavailableApprovalVersions.insert(key)
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
        guard let audience = approvalAudience(id: "audience-01"), let plan = plan(id: "plan-01") else {
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
            syncAnalytics(batchID: batch.id)
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

    private func restoreApprovalSeed() {
        revisionNotes = [:]
        resourceValid = [:]
        resourceReasons = [:]
        unavailableApprovalVersions = []
        reachFixtures = ["audience-01#1": 2000, "audience-02#1": 900,
                         "audience-03#1": 0, "audience-04#1": 400, "audience-05#1": 50]
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
                resourceSummary: plan.resourceSummary, resourceWasValid: isResourceValid(planID: plan.id, version: plan.version),
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
        let groups: [(id: String, version: Int)]
        if let frozen = snapshot(for: taskID) { groups = frozen.groups.map { ($0.planID, $0.planVersion) } }
        else { groups = task(id: taskID)?.allocation.groups.map { ($0.planID, $0.planVersion) } ?? [] }
        for group in groups where !isResourceValid(planID: group.id, version: group.version) {
            let name = plan(id: group.id)?.displayName ?? "方案"
            return "\(name) 发送版本资源已失效，不能继续发送。请先到方案模块处理。"
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
        guard var snapshot = self.audience(id: audience.id) else { return }
        snapshot.audience = audience
        snapshot.metadata.updatedAt = Date()
        if let index = audienceSnapshots.firstIndex(where: { $0.audience.id == audience.id }) {
            audienceSnapshots[index] = snapshot
        }
        versions.append(versionRecord(snapshot, source: .manualEdit, summary: "审批演示：发布人群版本", at: Date()))
    }

    private func archive(_ plan: MarketingPlan) {
        guard let index = plans.firstIndex(where: { $0.id == plan.id }) else { return }
        plans[index] = plan
        versions.append(.init(id: "plan:\(plan.id):\(plan.version)", objectKind: .plan,
                              objectID: plan.id, version: plan.version, createdAt: Date(),
                              changeSource: .manualEdit, summary: "审批演示：发布方案版本", content: .plan(plan)))
        recordPlanSnapshot(plan, source: .manual, summary: "审批演示：发布方案版本")
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

extension DemoSession {
    // A owns the underlying collection; C's stable public accessor is an alias.
    var tasks: [ApprovalTask] {
        get { approvalTasks }
        set { approvalTasks = newValue }
    }
    var approvalAudiences: [Audience] {
        audiences + Self.extraAudiences.filter { extra in !audiences.contains { $0.id == extra.id } }
    }
    private func syncAnalytics(batchID: String) {
        guard let batch = batch(id: batchID), batch.taskID != "task-history-01",
              let snapshot = snapshot(for: batch.taskID) else { return }
        let old = analyticsStatistics.batches[batchID]
        let groups = snapshot.groups.compactMap { frozen -> AnalyticsBatchInput.Group? in
            guard let counts = batch.groups.first(where: { $0.planID == frozen.planID }) else { return nil }
            return .init(planID: frozen.planID, planNumber: frozen.planNumber,
                         planVersion: frozen.planVersion, percentage: frozen.percentage,
                         allocated: counts.allocated, uniqueSucceeded: counts.succeeded,
                         sourceSnapshot: "\(frozen.purpose.rawValue) · \(frozen.customerStage.rawValue)\n\(frozen.message)\n\(frozen.resourceSummary)")
        }
        guard old?.groups != groups else { return }
        analyticsStatistics.receive(.init(id: batch.id, taskID: batch.taskID,
            audienceID: snapshot.audienceID, audienceNumber: snapshot.audienceNumber,
            audienceVersion: snapshot.audienceVersion, businessDate: batch.businessDate,
            revision: (old?.revision ?? -1) + 1, groups: groups))
    }
    @discardableResult
    func loadAnalyticsStatistics(batchID: String) -> Bool {
        guard analyticsStatistics.load(batchID: batchID) else { return false }
        if let index = batches.firstIndex(where: { $0.id == batchID }) {
            batches[index].statisticsStatus = .simulated
        }
        return true
    }
}

// B's write contract is implemented by the same observed session.
extension DemoSession: PlanSessionAccess {
    var storeResources: [StoreResource] { seed.storeResources }
    var planTemplates: [PlanTemplate] { seed.planTemplates }
    var planRuleRanges: [PlanRuleRange] { seed.planRuleRanges }
    var planReferenceDate: Date { Self.referenceDate }
    var planRecommendedPrimaryPercentage: Int { MockDataStore.planRecommendedPrimaryPercentage }
    var ruleGenerationAvailable: Bool { true }

    private func restorePlanSeed() {
        planMetadata = seed.planMetadata
        planVersions = seed.planVersions
        planSuggestions = seed.planSuggestions
        touchRules = seed.touchRules
        ruleGenerations = []
    }

    private func recordPlanSnapshot(_ plan: MarketingPlan, source: PlanChangeSource, summary: String) {
        guard let previous = planMetadata[plan.id] else { return }
        let now = Date()
        let info = PlanMetadata(resourceID: previous.resourceID, createdAt: previous.createdAt, updatedAt: now)
        planMetadata[plan.id] = info
        planVersions.append(.init(plan: plan, metadata: info,
                                  resource: storeResources.first { $0.id == info.resourceID },
                                  resourceCheckedAt: Self.referenceDate, changedAt: now,
                                  changeSource: source, summary: summary))
    }

    @discardableResult
    func savePlan(_ request: PlanSaveRequest) throws -> MarketingPlan {
        guard let revision = try PlanValidation.revision(request: request, plans: plans, metadata: planMetadata,
            resources: storeResources, audiences: audiences, referenceDate: Self.referenceDate,
            nextNumber: (plans.map(\.number).max() ?? 0) + 1, now: Date()) else {
            guard let existing = plan(id: request.id) else { throw PlanValidationError("方案不存在。") }
            return existing
        }
        commitPlanRevision(revision)
        return revision.plan
    }

    private func commitPlanRevision(_ revision: PlanRevision) {
        if let index = plans.firstIndex(where: { $0.id == revision.plan.id }) { plans[index] = revision.plan }
        else { plans.append(revision.plan) }
        planMetadata[revision.plan.id] = revision.metadata
        planVersions.append(revision.snapshot)
        versions.append(.init(id: "plan:\(revision.plan.id):\(revision.plan.version)", objectKind: .plan,
                              objectID: revision.plan.id, version: revision.plan.version,
                              createdAt: revision.snapshot.changedAt,
                              changeSource: revision.snapshot.changeSource == .aiAdoption ? .aiAdoption : .manualEdit,
                              summary: revision.snapshot.summary, content: .plan(revision.plan)))
    }

    @discardableResult
    func adoptPlanSuggestion(id: String) throws -> MarketingPlan {
        guard let index = planSuggestions.firstIndex(where: { $0.id == id }) else {
            throw PlanValidationError("建议不存在。")
        }
        let now = Date()
        let revision = try PlanValidation.adoption(suggestion: planSuggestions[index], plans: plans,
            metadata: planMetadata, resources: storeResources, audiences: audiences,
            referenceDate: Self.referenceDate, now: now)
        commitPlanRevision(revision)
        planSuggestions[index].status = .adopted
        planSuggestions[index].handledAt = now
        planSuggestions[index].resultingVersion = revision.plan.version
        return revision.plan
    }

    func deferPlanSuggestion(id: String) throws {
        guard let index = planSuggestions.firstIndex(where: { $0.id == id }),
              planSuggestions[index].status == .pending else { throw PlanValidationError("建议不在待处理状态。") }
        planSuggestions[index].status = .deferred
        planSuggestions[index].handledAt = Date()
    }

    @discardableResult
    func saveTouchRule(id: String, baseRevision: Int?, configuration: TouchRuleConfiguration) throws -> TouchRule {
        let value = try PlanValidation.rule(id: id, baseRevision: baseRevision, configuration: configuration,
            rules: touchRules, plans: plans, nextNumber: (touchRules.map(\.number).max() ?? 0) + 1, now: Date())
        if let index = touchRules.firstIndex(where: { $0.id == id }) { touchRules[index] = value }
        else { touchRules.append(value) }
        return value
    }

    func setTouchRuleEnabled(id: String, baseRevision: Int, enabled: Bool) throws {
        guard let current = touchRules.first(where: { $0.id == id }) else { throw PlanValidationError("规则不存在。") }
        var config = current.configuration
        config.isEnabled = enabled
        _ = try saveTouchRule(id: id, baseRevision: baseRevision, configuration: config)
    }

    @discardableResult
    func generatePendingTask(from preview: PlanRulePreview) throws -> PlanRuleGeneration {
        guard let rule = touchRules.first(where: { $0.id == preview.rule.id }) else { throw PlanValidationError("规则不存在。") }
        let current = try PlanValidation.preview(rule: rule, plans: plans, metadata: planMetadata,
            resources: storeResources, audiences: audiences, ranges: planRuleRanges, referenceDate: Self.referenceDate)
        try PlanValidation.validateGeneration(preview: preview, current: current, generations: ruleGenerations)
        let now = Date()
        let result = createPendingTask(request: .init(ruleID: rule.id, cycleKey: preview.cycleID,
            origin: rule.configuration.kind == .birthday ? .birthdayRule : .revisitRule,
            summary: "\(rule.displayName) · \(rule.configuration.conditionLabel) · 本地模拟",
            audienceID: preview.audience.id, audienceVersion: preview.audience.version,
            expectedReach: preview.expectedReach, allocation: preview.allocation), now: now)
        guard !result.isFailure,
              let task = tasks.first(where: { $0.ruleID == rule.id && $0.generationCycleKey == preview.cycleID }) else {
            throw PlanValidationError(result.message)
        }
        let generation = PlanRuleGeneration(taskID: task.id, taskNumber: task.number, createdAt: now, preview: preview)
        ruleGenerations.append(generation)
        return generation
    }
}
