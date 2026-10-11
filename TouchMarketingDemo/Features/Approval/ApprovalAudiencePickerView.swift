import SwiftUI

struct ApprovalAudiencePickerView: View {
    @Binding var draft: ApprovalFormDraft
    @Environment(DemoSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        DemoPage {
            Text("只选择本次任务的人群。这里不能改人群规则或评分。")
                .font(DemoTheme.Typography.body)
            if session.audienceRevision(id: draft.audienceID, version: draft.audienceVersion) == nil {
                DemoEmptyState(title: "当前引用不可用", message: "列表里没有这条引用。不会自动改选其他人群。")
            }
            ForEach(session.audiences.sorted { $0.number < $1.number }) { audience in
                audienceCard(audience)
            }
            if let message {
                Text(message)
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
            }
            Button("取消") { dismiss() }.buttonStyle(DemoSecondaryButtonStyle())
        }
        .navigationTitle("选择人群")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func audienceCard(_ audience: Audience) -> some View {
        let assessment = session.reachAssessment(audienceID: audience.id, version: audience.version)
        return DemoCard {
            Text(audience.displayName).font(DemoTheme.Typography.heading)
            DemoValueRow(title: "覆盖人数", value: "\(DemoFormat.count(audience.memberCount)) 人")
            DemoValueRow(title: "版本", value: "V\(audience.version)")
            DemoValueRow(title: "本次范围", value: reachLabel(assessment, audience: audience))
            ForEach(Array(audience.scores.prefix(3))) { score in
                DemoValueRow(title: score.dimension.rawValue, value: score.displayValue)
            }
            if audience.hasInsufficientEvidence {
                Text("评分依据不足。这不是零覆盖，核对后仍可能触达。")
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
            }
            Button("选择\(audience.displayName)") {
                draft.audienceID = audience.id
                draft.audienceVersion = audience.version
                dismiss()
            }
            .buttonStyle(DemoPrimaryButtonStyle())
        }
    }

    private func reachLabel(_ assessment: TaskReachState, audience: Audience) -> String {
        switch assessment {
        case .known:
            session.knownReach(audienceID: audience.id, version: audience.version)
                .map { "\(DemoFormat.count($0)) 人" } ?? "待核对"
        case .pendingReview: "待核对"
        case .zeroCoverage: "零覆盖"
        case .unavailable: "不可用"
        }
    }
}
