import SwiftUI

struct AudienceProfileView: View {
    let snapshot: AudienceSnapshot
    var coreOnly = false
    var body: some View {
        VStack(alignment: .leading, spacing: DemoTheme.Spacing.medium) {
            if !coreOnly || snapshot.recognition != .ready {
                Text(snapshot.recognition.rawValue).font(DemoTheme.Typography.caption)
            }
            ForEach(coreOnly ? Array(snapshot.audience.scores.prefix(3)) : snapshot.audience.scores) { score in
                VStack(alignment: .leading, spacing: DemoTheme.Spacing.small) {
                    DemoValueRow(title: score.dimension.rawValue, value: score.value == nil ? missingText : "\(score.displayValue) · \(score.level)")
                    if !coreOnly {
                        HStack(spacing: 4) {
                            ForEach(1...5, id: \.self) { step in
                                Rectangle().fill(step <= (score.value ?? 0) ? DemoTheme.ColorToken.black : DemoTheme.ColorToken.border).frame(height: 6)
                            }
                        }.accessibilityHidden(true)
                        Text(score.dimension.explanation).font(DemoTheme.Typography.caption).foregroundStyle(DemoTheme.ColorToken.secondaryText)
                    }
                }
            }
            if !coreOnly {
                Text("主要品类").font(DemoTheme.Typography.heading)
                if snapshot.audience.categoryPreferences.isEmpty {
                    Text(snapshot.recognition == .empty ? "覆盖为0，暂无品类分布" : missingText)
                }
                ForEach(snapshot.audience.categoryPreferences) { category in
                    DemoValueRow(title: category.name, value: "\(category.percentage)%")
                }
                Text("占比口径：\(snapshot.metadata.categoryBasis)").font(DemoTheme.Typography.caption)
            }
        }
    }
    private var missingText: String {
        switch snapshot.recognition {
        case .recognizing: "待识别"
        case .empty: "无覆盖样本"
        default: "依据不足"
        }
    }
}

struct AudienceRulesView: View {
    let rules: AudienceRules
    var body: some View {
        VStack(alignment: .leading, spacing: DemoTheme.Spacing.medium) {
            Text(rules.relation.rawValue).font(DemoTheme.Typography.heading)
            ForEach(rules.conditions) { condition in
                Text(condition.summary)
                Text("字段 V\(condition.field.version) · \(condition.field.explanation)")
                    .font(DemoTheme.Typography.caption).foregroundStyle(DemoTheme.ColorToken.secondaryText)
            }
            if !rules.instruction.isEmpty { Text("识别说明：\(rules.instruction)") }
        }
    }
}

struct AudienceScoreExplanationView: View {
    let metadata: AudienceProfileMetadata
    var body: some View {
        DemoPage {
            DemoCard {
                Text("统一解释量表").font(DemoTheme.Typography.heading)
                Text("1 低 · 2 偏低 · 3 中 · 4 偏高 · 5 高；缺失数据不计低分。")
                Text("各维度独立，不计算综合客户优质分。画像是群体宏观摘要，不代表每个客户。")
                DemoValueRow(title: "观察周期", value: metadata.observationPeriod)
                DemoValueRow(title: "量表版本", value: metadata.scaleVersion)
                DemoValueRow(title: "更新时间", value: DemoFormat.timestamp(metadata.updatedAt))
            }
            ForEach(AudienceScore.Dimension.allCases, id: \.self) { dimension in
                DemoCard {
                    Text(dimension.rawValue).font(DemoTheme.Typography.heading)
                    Text(dimension.explanation)
                }
            }
            Text("固定演示样本；未实现真实 AI 评分，正式阈值待细化。")
        }.navigationTitle("评分说明").navigationBarTitleDisplayMode(.inline)
    }
}
