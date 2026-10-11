import Foundation

@main
struct IntegratedSessionChecks {
    struct Failure: Error { let message: String }
    @MainActor
    static func main() throws {
        var count = 0
        func check(_ value: Bool, _ message: String) throws {
            guard value else { throw Failure(message: message) }
            count += 1
        }
        func rejects(_ message: String, _ action: () throws -> Void) throws {
            do { try action() } catch { count += 1; return }
            throw Failure(message: message)
        }
        let s = DemoSession()
        let query = AnalyticsQuery(period: .week, audienceID: nil, planIDs: [])
        try check(ApprovalExecutionMath.verify().isEmpty, "C execution math")
        try check(s.audiences.count == 2 && s.tasks.count == 2, "one shared seed, A catalog preserved")
        try check(s.approvalAudiences.count == 5, "C boundary fixtures remain available")
        try check(s.analyticsStatistics.batches.isEmpty, "history not counted twice")
        let oldAudience = s.audienceVersion(id: "audience-01", version: 1)!
        var rules = oldAudience.rules; rules.instruction = "integrated edit"
        _ = try s.saveAudience(id: "audience-01", baseVersion: 1, rules: rules)
        try check(s.approvalAudience(id: "audience-01")?.version == 2, "A edit visible to C")
        try check(s.audienceRevision(id: "audience-01", version: 1) == oldAudience.audience, "C pins A old version")
        try check(!s.versionDifferences(for: s.task(id: "task-01")!).isEmpty, "C warns about A version")
        try check(s.reachAssessment(audienceID: "audience-01", version: 2) == .pendingReview, "new scope stays unknown")
        try check(s.reachAssessment(audienceID: "audience-01", version: 1) == .known, "old ready version remains sendable")
        try check(s.confirmSend(taskID: "task-01", preset: .succeeded, acknowledgeVersionGap: false).isFailure, "version gap requires acknowledgment")
        s.reset()
        var edited = PlanContent(plan: s.plans[0], resourceID: s.planMetadata["plan-01"]?.resourceID)
        edited.message = "保存到统一会话的 V2"
        let v2 = try s.savePlan(.init(id: "plan-01", baseVersion: 1, content: edited, creationSource: .manual))
        try check(v2.version == 2 && s.plans[0].version == 2, "B save updates shared plans")
        try check(s.planRevision(id: "plan-01", version: 1)?.message != v2.message, "C retains old B version")
        try check(s.planVersions.first { $0.plan.id == "plan-01" && $0.plan.version == 1 }?.plan == MockDataStore.demo.plans[0], "B frozen resource snapshot")
        let unchanged = try s.savePlan(.init(id: "plan-01", baseVersion: 2, content: edited, creationSource: .manual))
        try check(unchanged.version == 2 && s.planVersions.count == 3, "unchanged save creates no version")
        try rejects("stale B edit") { _ = try s.savePlan(.init(id: "plan-01", baseVersion: 1, content: edited, creationSource: .manual)) }
        try rejects("stale B suggestion") { _ = try s.adoptPlanSuggestion(id: "plan-suggestion-01") }
        let created = try s.savePlan(.init(id: "plan-integrated", baseVersion: nil, content: edited, creationSource: .manual))
        try check(created.number == 3 && s.plan(id: created.id) != nil, "new B plan visible to C")
        try rejects("repeat create") { _ = try s.savePlan(.init(id: created.id, baseVersion: nil, content: edited, creationSource: .manual)) }
        var invalid = edited; invalid.resourceID = "resource-expired-01"
        try rejects("expired B resource") { _ = try s.savePlan(.init(id: "invalid", baseVersion: nil, content: invalid, creationSource: .manual)) }
        s.reset()
        let adopted = try s.adoptPlanSuggestion(id: "plan-suggestion-01")
        try check(adopted.version == 2 && s.planSuggestions[0].status == .adopted, "B adoption atomic")
        try rejects("repeat adoption") { _ = try s.adoptPlanSuggestion(id: "plan-suggestion-01") }
        s.reset()
        let half = ABAllocation(groups: [.init(planID: "plan-01", planVersion: 1, percentage: 50),
                                         .init(planID: "plan-02", planVersion: 1, percentage: 50)])!
        try check(!s.saveAdjustment(taskID: "task-01", audienceID: "audience-01", audienceVersion: 1, allocation: half).isFailure, "C save half allocation")
        try check(!s.confirmSend(taskID: "task-01", preset: .partiallyFailed, acknowledgeVersionGap: false).isFailure, "C confirm")
        try check(s.snapshots.count == 2 && s.batches.count == 2, "single new batch")
        let inputID = "batch-task-01"
        let frozen = s.snapshot(for: "task-01")!
        let pending = s.analyticsStatistics.report(batchID: inputID, query: query)
        try check(pending.completion == .pending && pending.totals.converted == nil, "D receives new waiting batch as pending")
        try check(!s.loadAnalyticsStatistics(batchID: inputID), "unmatched zero successes cannot load")
        let sameConfirm = s.confirmSend(taskID: "task-01", preset: .succeeded, acknowledgeVersionGap: false)
        try check(!sameConfirm.isFailure && s.batches.count == 2, "repeat confirm no extra batch")
        try check(!s.advance(batchID: inputID).isFailure && !s.advance(batchID: inputID).isFailure, "C execution progresses")
        try check(s.batch(id: inputID)?.succeededTotal == 1500, "C fixed partial failure")
        try check(s.analyticsStatistics.report(batchID: inputID, query: query).totals.reached == 1500, "D cumulative unique successes")
        try check(!s.loadAnalyticsStatistics(batchID: inputID), "partial scope has no fake conversion")
        try check(!s.startRetry(batchID: inputID, preset: .allSucceeded).isFailure, "C retry starts")
        try check(s.startRetry(batchID: inputID, preset: .allSucceeded).isFailure, "no parallel retry")
        try check(s.batch(id: inputID)?.succeededTotal == 1500, "retry start does not pre-count results")
        try check(!s.advance(batchID: inputID).isFailure, "retry finishes")
        try check(s.batch(id: inputID)?.succeededTotal == 2000 && s.batch(id: inputID)?.failedTotal == 0, "unique successes stop at original reach")
        try check(s.snapshot(for: "task-01") == frozen && s.batches.count == 2, "retry keeps frozen snapshot and batch")
        try check(s.analyticsStatistics.report(batchID: inputID, query: query).totals.reached == 2000, "D replaces 1500 with 2000")
        try check(s.loadAnalyticsStatistics(batchID: inputID), "D loads exact matching 50/50 fixture")
        try check(s.batch(id: inputID)?.statisticsStatus == .simulated, "C and D statistics state agree")
        let loaded = s.analyticsStatistics.report(batchID: inputID, query: query)
        try check(loaded.totals.converted == 130 && loaded.totals.orders == 150 && loaded.totals.cents == 2250000, "new sales differ from historical 168")
        try check(!s.loadAnalyticsStatistics(batchID: inputID) && s.analyticsStatistics.report(batchID: inputID, query: query) == loaded, "load idempotent")
        try check(s.advance(batchID: inputID).isFailure && s.analyticsStatistics.report(batchID: inputID, query: query) == loaded, "duplicate callback cannot erase loaded result")
        try check(s.analytics.totals.reachedCustomers == 2000 && s.analytics.totals.convertedCustomers == 168, "history unchanged")
        _ = s.simulatePlanRevision(id: "plan-01")
        try check(s.snapshot(for: "task-01") == frozen, "latest plan cannot overwrite confirmed content")
        s.reset()
        let rule = s.touchRules.first!
        let preview = try PlanValidation.preview(rule: rule, plans: s.plans, metadata: s.planMetadata,
            resources: s.storeResources, audiences: s.audiences, ranges: s.planRuleRanges, referenceDate: s.planReferenceDate)
        let generation = try s.generatePendingTask(from: preview)
        try check(s.task(id: generation.taskID)?.expectedReach == 24 && s.task(id: generation.taskID)?.approvalStatus == .pending, "B generates actual C pending task")
        try check(s.batch(for: generation.taskID) == nil, "rule generation does not send")
        try rejects("same-cycle generation") { _ = try s.generatePendingTask(from: preview) }
        try check(s.tasks.count == 3 && s.ruleGenerations.count == 1, "generation dedup single record")
        var generatedAllocation = s.task(id: generation.taskID)!.allocation
        generatedAllocation = ABAllocation(groups: [.init(planID: "plan-02", planVersion: 1, percentage: 100)])!
        _ = s.saveAdjustment(taskID: generation.taskID, audienceID: "audience-01", audienceVersion: 1, allocation: generatedAllocation)
        try check(s.task(id: generation.taskID)?.expectedReach == 24, "C adjustment preserves B rule scope")
        try check(s.adjustmentReach(taskID: generation.taskID, audienceID: "audience-01", version: 1) == 24, "C editor displays rule scope rather than whole audience fixture")
        let emptyGroup = ABAllocation(groups: [.init(planID: "plan-01", planVersion: 1, percentage: 1),
                                              .init(planID: "plan-02", planVersion: 1, percentage: 99)])!
        try check(s.saveAdjustment(taskID: generation.taskID, audienceID: "audience-01", audienceVersion: 1, allocation: emptyGroup).isFailure, "C rejects zero groups using 24-person rule scope")
        try check(!s.confirmSend(taskID: generation.taskID, preset: .succeeded, acknowledgeVersionGap: false).isFailure, "B-generated task confirms")
        s.reset()
        _ = s.setResourceInvalid(planID: "plan-02", invalid: true)
        try check(s.confirmSend(taskID: "task-01", preset: .succeeded, acknowledgeVersionGap: false).isFailure, "resource gate blocks confirmation")
        s.reset()
        _ = s.simulateAudienceRevision()
        _ = s.removePinnedAudienceSnapshot()
        try check(!s.pinnedContentAvailable(s.task(id: "task-01")!), "missing C snapshot is blocked")
        try check(s.audienceVersion(id: "audience-01", version: 1) != nil, "C missing-snapshot demo preserves A history")
        s.reset()
        _ = s.deferTask(taskID: "task-01")
        try check(s.tasks[0].approvalStatus == .deferred && s.approvalTasks[0].approvalStatus == .deferred, "task aliases share state")
        _ = s.rejectTask(taskID: "task-01", reason: "集成检查")
        try check(s.tasks[0].approvalStatus == .rejected && s.batch(for: "task-01") == nil, "reject never sends")
        let before = s.resetGeneration
        s.reset()
        try check(s.resetGeneration == before + 1 && s.audiences == MockDataStore.demo.audiences && s.plans == MockDataStore.demo.plans, "unified reset A and B")
        try check(s.tasks[0].approvalStatus == .pending && s.batches.count == 1 && s.snapshots.count == 1, "unified reset C retains only history")
        try check(s.ruleGenerations.isEmpty && s.analyticsStatistics.batches.isEmpty && s.analyticsStatistics.loaded.isEmpty, "unified reset B generated tasks and D stats")
        try check(s.planSuggestions[0].status == .pending && s.planVersions.count == 2, "reset suggestions and versions")
        print("PASS: \(count) integrated A/B/C/D session checks")
    }
}
