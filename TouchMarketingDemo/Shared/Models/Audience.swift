import Foundation

struct Audience: Identifiable, Hashable {
    let id: String
    let number: Int
    let memberCount: Int
    let source: CreationSource
    let version: Int
    let scores: [AudienceScore]
    let categoryPreferences: [CategoryPreference]

    var displayName: String { DemoFormat.numbered("人群", number) }

    func replacing(version: Int? = nil, scores: [AudienceScore]? = nil) -> Audience {
        Audience(
            id: id, number: number, memberCount: memberCount, source: source,
            version: version ?? self.version,
            scores: scores ?? self.scores,
            categoryPreferences: categoryPreferences
        )
    }

    var hasInsufficientEvidence: Bool { scores.contains { $0.value == nil } }
}

enum CreationSource: String, CaseIterable {
    case ai = "AI 创建"
    case manual = "手动创建"
}

struct AudienceScore: Identifiable, Hashable {
    enum Dimension: String, CaseIterable {
        case spending = "消费水平"
        case frequency = "购买频次"
        case priceSensitivity = "价格敏感度"
        case newProducts = "新品偏好"
        case classics = "经典款偏好"
    }
    let dimension: Dimension
    /// nil 表示依据不足，不能用 0 或低分替代；有效分值为 1...5。
    let value: Int?
    var id: Dimension { dimension }
    var displayValue: String { value.map { "\($0) / 5" } ?? "依据不足" }
}

struct CategoryPreference: Identifiable, Hashable {
    let id: String
    let name: String
    /// 0...100，示例口径暂按购买件数；正式统计口径仍待产品细化。
    let percentage: Int
}
