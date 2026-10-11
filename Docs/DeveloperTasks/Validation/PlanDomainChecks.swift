import Foundation

// 独立 smoke executable，不新增 Xcode target，不引入依赖。
@main
enum PlanDomainChecks {
    struct Failure: Error { let message: String }
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(message: message) }
    }
    static func rejects(_ message: String, _ action: () throws -> Void) throws {
        do { try action() }
        catch is PlanValidationError { return }
        throw Failure(message: message)
    }

    static func main() throws {
        let seed = MockDataStore.demo
        let day = MockDataStore.planReferenceDate
        let now = day.addingTimeInterval(3600)
        guard let original = seed.plans.first, let info = seed.planMetadata[original.id] else {
            throw Failure(message: "Missing seed")
        }
        let oldSnapshot = seed.planVersions.first
        let content = PlanContent(plan: original, resourceID: info.resourceID)
        func revise(_ content: PlanContent, id: String = "plan-01", base: Int? = 1,
                    plans: [MarketingPlan]? = nil, metadata: [String: PlanMetadata]? = nil) throws -> PlanRevision? {
            try PlanValidation.revision(request: .init(id: id, baseVersion: base, content: content, creationSource: .manual),
                                        plans: plans ?? seed.plans, metadata: metadata ?? seed.planMetadata,
                                        resources: seed.storeResources, audiences: seed.audiences,
                                        referenceDate: day, nextNumber: 3, now: now)
        }

        var blank = content; blank.message = " \n\t "
        try rejects("Empty content accepted") { _ = try revise(blank) }
        var expired = content; expired.resourceID = "resource-expired-01"
        try rejects("Expired resource accepted") { _ = try revise(expired) }
        var missing = content; missing.audienceIDs.append("missing-audience")
        try rejects("Missing audience accepted") { _ = try revise(missing) }
        missing = content; missing.resourceID = "missing-resource"
        try rejects("Missing resource accepted") { _ = try revise(missing) }
        for resource in seed.storeResources where resource.unavailableReason == nil {
            try check(resource.invalidReason(on: day) == nil, "Usable fixture rejected")
            try check(resource.invalidReason(on: resource.validFrom.addingTimeInterval(-1)) != nil, "Future resource accepted")
            try check(resource.invalidReason(on: resource.validThrough.addingTimeInterval(1)) != nil, "Expiry not enforced")
        }

        var equivalent = content
        equivalent.message = "  " + content.message + "\n"
        equivalent.audienceIDs = Array(content.audienceIDs.reversed()) + content.audienceIDs
        let unchanged = try revise(equivalent)
        try check(unchanged == nil, "Equivalent content created extra version")
        var edited = content; edited.message = "新的关怀话术"; edited.resourceID = nil
        guard let revision = try revise(edited) else { throw Failure(message: "Expected revision") }
        try check(revision.plan.version == 2 && revision.plan.number == original.number, "Version or number changed incorrectly")
        try check(revision.plan.source == original.source, "Original creation source lost")
        try check(revision.snapshot.resource == nil, "Removed resource retained")
        try check(oldSnapshot?.plan.message == original.message && oldSnapshot?.resource?.id == info.resourceID, "Old snapshot mutated")
        try check(seed.approvalTasks.allSatisfy { $0.allocation.groups.allSatisfy { $0.planVersion == 1 } }, "Old tasks upgraded")
        let newerPlans = seed.plans.map { $0.id == revision.plan.id ? revision.plan : $0 }
        var newerMetadata = seed.planMetadata; newerMetadata[revision.plan.id] = revision.metadata
        try rejects("Stale edit overwrote current") { _ = try revise(edited, plans: newerPlans, metadata: newerMetadata) }
        guard let created = try revise(edited, id: "plan-new-check", base: nil) else { throw Failure(message: "Expected create") }
        try check(created.plan.version == 1 && created.plan.number == 3, "New plan numbering")
        try rejects("Duplicate create accepted") { _ = try revise(edited, id: created.plan.id, base: nil, plans: seed.plans + [created.plan]) }

        guard let suggestion = seed.planSuggestions.first else { throw Failure(message: "Missing suggestion") }
        let adoption = try PlanValidation.adoption(suggestion: suggestion, plans: seed.plans, metadata: seed.planMetadata,
                                                   resources: seed.storeResources, audiences: seed.audiences, referenceDate: day, now: now)
        try check(adoption.plan.version == 2 && adoption.snapshot.changeSource == .aiAdoption, "Adoption did not make version")
        var adopted = suggestion; adopted.status = .adopted
        try rejects("Repeated adoption accepted") {
            _ = try PlanValidation.adoption(suggestion: adopted, plans: seed.plans, metadata: seed.planMetadata,
                                           resources: seed.storeResources, audiences: seed.audiences, referenceDate: day, now: now)
        }
        try rejects("Old suggestion overwrote V2") {
            _ = try PlanValidation.adoption(suggestion: suggestion, plans: newerPlans, metadata: newerMetadata,
                                           resources: seed.storeResources, audiences: seed.audiences, referenceDate: day, now: now)
        }
        guard let invalidSuggestion = seed.planSuggestions.last else { throw Failure(message: "Missing invalid suggestion") }
        try rejects("AI suggestion bypassed resource check") {
            _ = try PlanValidation.adoption(suggestion: invalidSuggestion, plans: seed.plans, metadata: seed.planMetadata,
                                           resources: seed.storeResources, audiences: seed.audiences, referenceDate: day, now: now)
        }

        guard let birthday = seed.touchRules.first, let follow = seed.touchRules.last else { throw Failure(message: "Missing rules") }
        func preview(_ rule: TouchRule) throws -> PlanRulePreview {
            try PlanValidation.preview(rule: rule, plans: seed.plans, metadata: seed.planMetadata,
                                       resources: seed.storeResources, audiences: seed.audiences,
                                       ranges: seed.planRuleRanges, referenceDate: day)
        }
        let birthdayPreview = try preview(birthday)
        let followPreview = try preview(follow)
        try check(birthdayPreview.expectedReach == 24 && birthdayPreview.allocation.groups.count == 1, "Birthday fixture")
        try check(followPreview.expectedReach == 120 && followPreview.allocation.expectedCounts(total: 120) == [36, 84], "Follow-up allocation")
        try check(birthdayPreview.cycleID == "2026-10-11", "Shanghai cycle")
        try check(followPreview.cutoffDate == Date(timeIntervalSince1970: 1_783_699_200), "Calendar month cutoff must be July 11")
        try PlanValidation.validateGeneration(preview: followPreview, current: followPreview, generations: [])
        let generation = PlanRuleGeneration(taskID: "task-check", taskNumber: 3, createdAt: now, preview: followPreview)
        try rejects("Duplicate cycle accepted") {
            try PlanValidation.validateGeneration(preview: followPreview, current: followPreview, generations: [generation])
        }
        var changed = follow.configuration; changed.hour = 10
        let changedRule = try PlanValidation.rule(id: follow.id, baseRevision: 1, configuration: changed,
                                                  rules: seed.touchRules, plans: seed.plans, nextNumber: 3, now: now)
        let changedPreview = try preview(changedRule)
        try rejects("Stale preview accepted") {
            try PlanValidation.validateGeneration(preview: followPreview, current: changedPreview, generations: [])
        }
        try rejects("Config change bypassed cycle dedup") {
            try PlanValidation.validateGeneration(preview: changedPreview, current: changedPreview, generations: [generation])
        }
        try check(generation.preview.rule.configuration.hour == 9 && generation.preview.plans.first?.plan.version == 1, "Generation snapshot mutated")
        changed = follow.configuration; changed.period = .sixMonths
        let zeroRule = try PlanValidation.rule(id: follow.id, baseRevision: 1, configuration: changed,
                                               rules: seed.touchRules, plans: seed.plans, nextNumber: 3, now: now)
        let zero = try preview(zeroRule)
        try check(zero.expectedReach == 0, "Zero fixture")
        try rejects("Zero reach generated") { try PlanValidation.validateGeneration(preview: zero, current: zero, generations: []) }
        changed = follow.configuration; changed.isEnabled = false
        let disabledRule = try PlanValidation.rule(id: follow.id, baseRevision: 1, configuration: changed,
                                                   rules: seed.touchRules, plans: seed.plans, nextNumber: 3, now: now)
        let disabled = try preview(disabledRule)
        try rejects("Disabled rule generated") { try PlanValidation.validateGeneration(preview: disabled, current: disabled, generations: []) }
        changed = follow.configuration; changed.secondaryPlanID = changed.primaryPlanID
        try rejects("Duplicate plans accepted") { _ = try PlanValidation.allocation(configuration: changed, plans: seed.plans) }
        changed = follow.configuration; changed.primaryPercentage = 0
        try rejects("Zero percent accepted") { _ = try PlanValidation.allocation(configuration: changed, plans: seed.plans) }
        changed = birthday.configuration; changed.primaryPercentage = 30
        try rejects("Single plan less than 100 accepted") { _ = try PlanValidation.allocation(configuration: changed, plans: seed.plans) }
        print("PASS: plan validation, immutable revisions, resource validity, suggestion guards, rule preview and cycle dedup")
    }
}
