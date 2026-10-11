import SwiftUI

struct ApprovalAllocationEditor: View {
    @Binding var draft: ApprovalFormDraft
    let reach: Int?
    let recommendation: String
    let planName: (String, Int) -> String
    let onRestore: () -> Void
    let onAddSecond: () -> Void
    let onRemoveLast: () -> Void

    @State private var attempt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DemoTheme.Spacing.medium) {
            Text("分配").font(DemoTheme.Typography.heading)
            Text("推荐比例 \(recommendation)。恢复推荐只改草稿，不覆盖原来的推荐值。")
                .font(DemoTheme.Typography.caption)
                .foregroundStyle(DemoTheme.ColorToken.secondaryText)
            ForEach(Array(draft.slots.enumerated()), id: \.offset) { index, slot in
                DemoValueRow(title: "\(ApprovalDisplay.letter(index)) 组方案", value: planName(slot.planID, slot.planVersion))
                DemoValueRow(title: "\(ApprovalDisplay.letter(index)) 组版本", value: "V\(slot.planVersion)")
            }
            if draft.slots.count <= 1 {
                DemoValueRow(title: "比例", value: "100%")
                DemoValueRow(title: "预计人数", value: reach.map { "\(DemoFormat.count($0)) 人" } ?? "待核对")
            } else {
                dualControls
            }
            if let message = draft.validationMessage(reach: reach) {
                Text(message)
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
            }
            if let attempt {
                Text(attempt)
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
            }
            Button("恢复推荐比例") {
                attempt = nil
                onRestore()
            }
            .buttonStyle(DemoSecondaryButtonStyle())
            Button(draft.slots.count >= 2 ? "添加第三套方案" : "添加第二套方案") {
                if draft.slots.count >= 2 {
                    attempt = "最多两套方案，不能添加第三套。"
                } else {
                    attempt = nil
                    onAddSecond()
                }
            }
            .buttonStyle(DemoSecondaryButtonStyle())
            Button("移除一套方案") {
                if draft.slots.count <= 1 {
                    attempt = "至少保留一套方案，不能空组后再发送。"
                } else {
                    attempt = nil
                    onRemoveLast()
                }
            }
            .buttonStyle(DemoSecondaryButtonStyle())
            Text("合计 100%。每位客户只接收一套方案。去重先于分组；预计人数是固定样本，不是客户名单。")
                .font(DemoTheme.Typography.caption)
                .foregroundStyle(DemoTheme.ColorToken.secondaryText)
        }
    }

    @ViewBuilder
    private var dualControls: some View {
        TextField("A 组整数百分比", text: $draft.primaryPercentText)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .font(DemoTheme.Typography.body)
            .accessibilityIdentifier("approval.percent")
        Stepper {
            Text("A 组步进")
        } onIncrement: {
            guard let value = ApprovalAllocationRules.parsedPercent(draft.primaryPercentText), value < 99 else { return }
            draft.primaryPercentText = String(value + 1)
        } onDecrement: {
            guard let value = ApprovalAllocationRules.parsedPercent(draft.primaryPercentText), value > 1 else { return }
            draft.primaryPercentText = String(value - 1)
        }
        if let percent = ApprovalAllocationRules.parsedPercent(draft.primaryPercentText), (1...99).contains(percent) {
            Slider(value: Binding(
                get: { Double(percent) },
                set: { draft.primaryPercentText = String(Int($0.rounded())) }
            ), in: 1...99, step: 1)
            .accessibilityIdentifier("approval.slider")
            DemoValueRow(title: "A / B", value: "\(percent)% / \(100 - percent)%")
            if let reach, let allocation = draft.makeAllocation() {
                let counts = allocation.expectedCounts(total: reach)
                DemoValueRow(title: "预计人数", value: counts.map { "\(DemoFormat.count($0)) 人" }.joined(separator: " / "))
            } else {
                DemoValueRow(title: "预计人数", value: "待核对")
            }
        }
    }
}
