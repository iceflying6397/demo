import Foundation

struct ApprovalFormDraft: Equatable {
    struct Slot: Equatable, Identifiable {
        var planID: String
        var planVersion: Int
        var id: String { "\(planID)-v\(planVersion)" }
    }

    var audienceID: String
    var audienceVersion: Int
    var slots: [Slot]
    var primaryPercentText: String

    static func from(task: ApprovalTask) -> ApprovalFormDraft {
        ApprovalFormDraft(
            audienceID: task.audienceID,
            audienceVersion: task.audienceVersion,
            slots: task.allocation.groups.map { Slot(planID: $0.planID, planVersion: $0.planVersion) },
            primaryPercentText: task.allocation.groups.first.map { String($0.percentage) } ?? "100"
        )
    }

    func matches(_ task: ApprovalTask) -> Bool {
        guard audienceID == task.audienceID, audienceVersion == task.audienceVersion else { return false }
        let saved = task.allocation.groups.map { Slot(planID: $0.planID, planVersion: $0.planVersion) }
        guard slots == saved else { return false }
        guard slots.count == 2 else { return true }
        return ApprovalAllocationRules.parsedPercent(primaryPercentText) == task.allocation.groups[0].percentage
    }

    func validationMessage(reach: Int?) -> String? {
        ApprovalAllocationRules.validate(slots: inputs, primaryPercentText: primaryPercentText, reach: reach)
    }

    func makeAllocation() -> ABAllocation? {
        ApprovalAllocationRules.make(slots: inputs, primaryPercentText: primaryPercentText)
    }

    private var inputs: [ApprovalSlotInput] {
        slots.map { ApprovalSlotInput(planID: $0.planID, planVersion: $0.planVersion) }
    }
}

enum ApprovalDisplay {
    static func reachText(for task: ApprovalTask) -> String {
        switch task.reachState {
        case .known: "\(DemoFormat.count(task.expectedReach)) 人"
        case .pendingReview: "待核对"
        case .zeroCoverage: "0 人 · 零覆盖"
        case .unavailable: "不可用"
        }
    }

    static func letter(_ index: Int) -> String { index == 0 ? "A" : "B" }
}
