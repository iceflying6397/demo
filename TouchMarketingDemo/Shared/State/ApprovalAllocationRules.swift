import Foundation

struct ApprovalSlotInput: Equatable {
    var planID: String
    var planVersion: Int
}

enum ApprovalAllocationRules {
    static func parsedPercent(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digits = trimmed.first == "-" ? trimmed.dropFirst() : Substring(trimmed)
        guard !digits.isEmpty, digits.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        if trimmed.count > 1, trimmed.first == "0" { return nil }
        if trimmed.hasPrefix("-0") { return nil }
        return Int(trimmed)
    }

    static func make(slots: [ApprovalSlotInput], primaryPercentText: String) -> ABAllocation? {
        let groups: [ABAllocation.Group]
        if slots.count == 1 {
            groups = [.init(planID: slots[0].planID, planVersion: slots[0].planVersion, percentage: 100)]
        } else if slots.count == 2, let percent = parsedPercent(primaryPercentText), (1...99).contains(percent) {
            groups = [
                .init(planID: slots[0].planID, planVersion: slots[0].planVersion, percentage: percent),
                .init(planID: slots[1].planID, planVersion: slots[1].planVersion, percentage: 100 - percent)
            ]
        } else {
            return nil
        }
        return ABAllocation(groups: groups)
    }

    static func validate(slots: [ApprovalSlotInput], primaryPercentText: String, reach: Int?) -> String? {
        if slots.isEmpty { return "至少保留一套方案，不能空组后再发送。" }
        if slots.count > 2 { return "最多两套方案，不能添加第三套。" }
        if slots.contains(where: { $0.planID.isEmpty || $0.planVersion <= 0 }) {
            return "方案不可用，不能保存。"
        }
        if Set(slots.map(\.planID)).count != slots.count {
            return "同一方案不能同时放在两个组。"
        }
        if slots.count == 2 {
            let trimmed = primaryPercentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let percent = parsedPercent(trimmed) else {
                return trimmed.isEmpty ? "百分比还是空的，不能保存。" : "百分比需为整数，当前输入不能保存。"
            }
            if percent < 0 { return "百分比不能为负数。" }
            if percent == 0 || percent == 100 {
                return "\(percent)% 已经不是双组测试，请改成单方案后再保存。"
            }
            if !(1...99).contains(percent) { return "双组比例需要是 1 到 99 的整数。" }
        }
        guard make(slots: slots, primaryPercentText: primaryPercentText) != nil else {
            return "分配无效，不能保存。"
        }
        if let reach, reach > 0,
           let allocation = make(slots: slots, primaryPercentText: primaryPercentText),
           allocation.expectedCounts(total: reach).contains(0) {
            return "某一组预计人数为 0。请调整比例，或改成单方案。"
        }
        return nil
    }
}
