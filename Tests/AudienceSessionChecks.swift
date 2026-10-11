import Foundation

@main
struct AudienceSessionChecks {
    @MainActor
    static func main() throws {
        let session = DemoSession()
        let initialTasks = session.approvalTasks
        var count = 0
        func check(_ success: @autoclosure () -> Bool, _ name: String) throws {
            guard success() else { throw DemoValidationError(message: "FAIL: \(name)") }
            count += 1
        }
        func rejects(_ name: String, _ body: () throws -> Void) throws {
            do { try body() } catch { count += 1; return }
            throw DemoValidationError(message: "FAIL: accepted \(name)")
        }
        let original = session.audience(id: "audience-01")!
        try check(session.audiences.count == 2 && original.audience.memberCount == 8420, "initial audience")
        try check(original.audience.scores.map(\.value) == [4, 2, 1, 5, 2], "initial scores")
        try check(session.coverage(for: session.audiences) == 11000, "explicit deduplicated union")
        try check(session.audiences.filter { $0.source == .ai }.count == 1, "source filter")
        try check(session.audiences.filter { $0.source == .manual }.count == 1, "manual filter")
        let unchanged = try session.saveAudience(id: "audience-01", baseVersion: 1, rules: original.rules)
        try check(unchanged.audience.version == 1 && session.history(kind: .audience, id: "audience-01").count == 1, "no-change save")
        var invalid = original.rules; invalid.conditions = []
        try rejects("empty rules") { try session.saveAudience(id: nil, baseVersion: nil, rules: invalid) }
        invalid.conditions = [original.rules.conditions[0], original.rules.conditions[0]]
        try rejects("duplicate conditions") { try session.saveAudience(id: nil, baseVersion: nil, rules: invalid) }
        let numberField = session.fields[0]
        invalid.conditions = [.init(id: "bad", field: numberField, operation: .between, value: .range(90, 30))]
        try rejects("invalid range") { try session.saveAudience(id: nil, baseVersion: nil, rules: invalid) }
        invalid.conditions = [.init(id: "bad", field: numberField, operation: .equals, value: .number(.nan))]
        try rejects("NaN") { try session.saveAudience(id: nil, baseVersion: nil, rules: invalid) }
        invalid.conditions = [.init(id: "bad", field: numberField, operation: .after, value: .date(DemoClock.referenceDate))]
        try rejects("type mismatch") { try session.saveAudience(id: nil, baseVersion: nil, rules: invalid) }
        var draft = original.rules; draft.instruction = "新规则说明"
        try check(session.audience(id: "audience-01") == original, "local draft cancellation")
        let v2 = try session.saveAudience(id: "audience-01", baseVersion: 1, rules: draft)
        try check(v2.audience.version == 2 && v2.audience.number == 1 && v2.audience.id == "audience-01", "edit stable identity")
        try check(v2.recognition == .recognizing && v2.audience.scores.allSatisfy { $0.value == nil }, "new version has unknown profile")
        try check(session.audienceVersion(id: "audience-01", version: 1) == original, "V1 immutable")
        try check(session.approvalStore.audience(id: "audience-01")?.version == 1, "approval keeps V1 profile")
        try check(session.approvalTasks.first?.audienceVersion == 1, "task keeps version reference")
        try check(session.coverage(for: session.audiences) == nil, "edited union unknown")
        try rejects("stale edit") { try session.saveAudience(id: "audience-01", baseVersion: 1, rules: draft) }
        try rejects("stale suggestion") { try session.adoptSuggestion(id: "suggestion-audience-valid") }
        try session.completeRecognition(id: "audience-01", version: 2, scenario: .insufficient)
        try check(session.audience(id: "audience-01")?.audience.scores.allSatisfy { $0.value == nil } == true, "insufficient is nil")
        try check(session.history(kind: .audience, id: "audience-01").count == 2, "recognition creates no version")
        try rejects("repeat recognition") { try session.completeRecognition(id: "audience-01", version: 2, scenario: .ready) }
        let created = try session.saveAudience(id: nil, baseVersion: nil, rules: draft)
        try check(created.audience.number == 3 && created.audience.version == 1, "new stable number")
        try check(session.store.audience(id: created.audience.id) != nil, "new audience visible in shared store")
        try session.completeRecognition(id: created.audience.id, version: 1, scenario: .empty)
        try check(session.audience(id: created.audience.id)?.recognition == .empty && session.coverage(for: [session.audience(id: created.audience.id)!.audience]) == 0, "zero coverage")
        let ready = try session.saveAudience(id: nil, baseVersion: nil, rules: draft)
        try session.completeRecognition(id: ready.audience.id, version: 1, scenario: .ready)
        try check(session.audience(id: ready.audience.id)?.audience.scores == original.audience.scores, "deterministic ready fixture")
        var field = AudienceField(id: "custom", name: "  客户偏好  ", type: .category, explanation: "自定义偏好", options: ["低", "高"], evidence: "固定样本", isEnabled: true, version: 0, isBuiltIn: false)
        field = try session.saveField(field)
        try check(field.name == "客户偏好" && field.version == 1, "field trim and version")
        var duplicate = field; duplicate = .init(id: "duplicate", name: field.name, type: .category, explanation: field.explanation, options: field.options, evidence: field.evidence, isEnabled: true, version: 0, isBuiltIn: false)
        try rejects("duplicate name") { try session.saveField(duplicate) }
        duplicate.name = "新名字"; duplicate.options = ["高", " 高 "]
        try rejects("duplicate category values") { try session.saveField(duplicate) }
        var customRules = original.rules
        customRules.conditions = [.init(id: "custom-rule", field: field, operation: .equals, value: .category("高"))]
        let customAudience = try session.saveAudience(id: nil, baseVersion: nil, rules: customRules)
        var fieldV2 = field; fieldV2.options = ["新选项"]
        fieldV2 = try session.saveField(fieldV2)
        try check(session.audienceVersion(id: customAudience.audience.id, version: 1)?.rules.conditions[0].field.options == ["低", "高"], "frozen field definition")
        fieldV2.isEnabled = false; _ = try session.saveField(fieldV2)
        try rejects("disabled field in new rule") { try session.saveAudience(id: nil, baseVersion: nil, rules: customRules) }
        _ = try session.saveAudience(id: customAudience.audience.id, baseVersion: 1, rules: customRules)
        try check(session.audience(id: customAudience.audience.id)?.audience.version == 1, "disabled old rule readable and unchanged")
        try rejects("stale field draft") { try session.saveField(field) }
        let dateField = session.fields.first { $0.type == .date }!
        let boolField = session.fields.first { $0.type == .boolean }!
        let typedRules = AudienceRules(relation: .or, conditions: [
            .init(id: "date", field: dateField, operation: .before, value: .date(DemoClock.referenceDate)),
            .init(id: "bool", field: boolField, operation: .equals, value: .boolean(true))
        ], instruction: "日期与布尔")
        _ = try session.saveAudience(id: nil, baseVersion: nil, rules: typedRules)
        try check(true, "date boolean OR support")
        session.reset()
        try check(session.audiences == MockDataStore.demo.audiences && session.fields == MockDataStore.audienceFields && session.resetGeneration == 1, "reset all audiences fields")
        try check(session.approvalTasks == initialTasks && session.plans == MockDataStore.demo.plans, "reset other modules")
        let beforeSuggestion = session.audience(id: "audience-01")
        try check(session.suggestions.first?.status == .pending && beforeSuggestion?.audience.version == 1, "view and cancel suggestion no mutation")
        try session.deferSuggestion(id: "suggestion-audience-valid")
        try check(session.audience(id: "audience-01") == beforeSuggestion && session.suggestions.first?.status == .deferred, "defer no audience changes")
        let adopted = try session.adoptSuggestion(id: "suggestion-audience-valid")
        try check(adopted.audience.version == 2 && session.suggestions.first?.generatedVersion == 2 && session.suggestions.first?.processedAt != nil, "adopt atomically")
        try rejects("repeat adoption") { try session.adoptSuggestion(id: "suggestion-audience-valid") }
        try rejects("expired suggestion") { try session.adoptSuggestion(id: "suggestion-audience-expired") }
        try check(session.audienceVersion(id: "audience-01", version: 1) == original, "adoption preserves V1")
        try check(session.planVersion(id: "plan-01", version: 1) == MockDataStore.demo.plans[0], "typed plan snapshot")
        var numericDraft = AudienceConditionDraft(field: numberField); numericDraft.text = "bad"
        try rejects("numeric parser") { _ = try numericDraft.condition() }
        numericDraft.text = "3.5"
        let parsed = try numericDraft.condition()
        try check(parsed.value == .number(3.5), "numeric parser accepts decimal")
        session.reset()
        let oldPlan = session.plans[0]
        let planV2 = MarketingPlan(id: oldPlan.id, number: oldPlan.number, purpose: oldPlan.purpose,
                                  customerStage: oldPlan.customerStage, version: 2, message: "新版话术",
                                  resourceSummary: oldPlan.resourceSummary, source: oldPlan.source, audienceIDs: oldPlan.audienceIDs)
        try session.savePlan(planV2, baseVersion: 1)
        try check(session.plans[0].version == 2 && session.planVersion(id: oldPlan.id, version: 1) == oldPlan, "plan update retains typed V1")
        try check(session.approvalStore.plan(id: oldPlan.id) == oldPlan, "approval keeps old plan snapshot")
        try rejects("stale plan save") { try session.savePlan(planV2, baseVersion: 1) }
        let pending = session.approvalTasks[0]
        let deferred = ApprovalTask(id: pending.id, number: pending.number, audienceID: pending.audienceID,
                                    audienceVersion: pending.audienceVersion, expectedReach: pending.expectedReach,
                                    allocation: pending.allocation, approvalStatus: .deferred, deliveryStatus: nil)
        try session.updatePendingTask(deferred)
        try check(session.approvalTasks[0].approvalStatus == .deferred, "pending draft update")
        try rejects("rewrite confirmed history") { try session.updatePendingTask(session.approvalTasks[1]) }
        let seedAnalytics = session.analytics
        session.reset()
        try check(session.analytics.id == seedAnalytics.id && session.analytics.totals.revenueInCents == 2940000, "reset analytics remains independent")
        var immutableBuiltIn = session.fields[0]
        immutableBuiltIn.name = "另一种含义"
        try rejects("built-in meaning change") { try session.saveField(immutableBuiltIn) }
        var forged = session.fields[0]
        forged = .init(id: forged.id, name: forged.name, type: forged.type, explanation: forged.explanation,
                       options: forged.options, evidence: forged.evidence, isEnabled: forged.isEnabled,
                       version: forged.version, isBuiltIn: false)
        try rejects("built-in identity change") { try session.saveField(forged) }
        let emptySeed = MockDataStore(audiences: [], plans: [], approvalTasks: [], analytics: MockDataStore.demo.analytics)
        let emptySession = DemoSession(store: emptySeed)
        try check(emptySession.audiences.isEmpty && emptySession.coverage(for: []) == 0, "empty seed")
        let day = DemoClock.calendar.component(.day, from: DemoClock.referenceDate)
        try check(day == 11, "shared Shanghai reference date")
        print("PASS: \(count) audience/session checks")
    }
}
