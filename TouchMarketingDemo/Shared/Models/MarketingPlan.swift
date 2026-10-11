import Foundation

struct MarketingPlan: Identifiable, Hashable {
    let id: String
    let number: Int
    let purpose: PlanPurpose
    let customerStage: CustomerStage
    let version: Int
    let message: String
    let resourceSummary: String
    let source: CreationSource
    /// 多对多关联唯一来源；Audience 不重复保存反向关系。
    let audienceIDs: [String]

    var displayName: String { DemoFormat.numbered("方案", number) }

    func replacing(version: Int? = nil, message: String? = nil) -> MarketingPlan {
        MarketingPlan(
            id: id, number: number, purpose: purpose, customerStage: customerStage,
            version: version ?? self.version, message: message ?? self.message,
            resourceSummary: resourceSummary, source: source, audienceIDs: audienceIDs
        )
    }
}

enum PlanPurpose: String, CaseIterable {
    case nurture = "新客培育"
    case firstPurchase = "首购转化"
    case repurchase = "复购促进"
    case valueGrowth = "价值提升"
    case relationship = "关系维护"
    case winBack = "流失召回"
}

enum CustomerStage: String, CaseIterable {
    case newContact = "新建立联系客户"
    case beforeFirstPurchase = "未首购客户"
    case purchased = "已购客户"
    case repeatBuyer = "持续复购客户"
    case lowActivity = "低活跃客户"
    case longInactive = "长期未购客户"
    case any = "不限客户阶段"
}
