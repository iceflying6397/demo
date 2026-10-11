import Foundation

/// 只读种子增补，仍由 MockDataStore 统一提供。A 初始化会话时读取一次。
extension MockDataStore {
    static let planReferenceDate = Date(timeIntervalSince1970: 1_791_648_000) // 上海 2026/10/11 00:00
    static let planSeedDate = Date(timeIntervalSince1970: 1_791_129_600)
    static let planRecommendedPrimaryPercentage = 30

    var storeResources: [StoreResource] {
        let start = Self.planSeedDate
        let end = Date(timeIntervalSince1970: 1_793_462_399) // 上海 2026/10/31 23:59:59
        return [
            .init(id: "resource-coupon-01", kind: .coupon, name: "回购礼遇券", detail: "满 100 元减 20 元，仅为店铺既有资源样本。",
                  amountInCents: 2_000, minimumSpendInCents: 10_000, category: nil,
                  validFrom: start, validThrough: end, unavailableReason: nil, demoURL: nil),
            .init(id: "resource-product-01", kind: .product, name: "日常关怀组合", detail: "在售商品样本，不访问店铺。",
                  amountInCents: 15_000, minimumSpendInCents: nil, category: "品类 A",
                  validFrom: start, validThrough: end, unavailableReason: nil, demoURL: "https://example.invalid/products/demo-01"),
            .init(id: "resource-lottery-01", kind: .lottery, name: "会员关怀抽奖", detail: "已有活动；样本奖项为会员礼遇，不在 App 配置奖品。",
                  amountInCents: nil, minimumSpendInCents: nil, category: nil,
                  validFrom: start, validThrough: end, unavailableReason: nil, demoURL: nil),
            .init(id: "resource-expired-01", kind: .coupon, name: "已结束的回购券", detail: "失效边界样本，需更换为有效资源。",
                  amountInCents: 1_000, minimumSpendInCents: 5_000, category: nil,
                  validFrom: start, validThrough: start, unavailableReason: "活动已结束", demoURL: nil)
        ]
    }

    var planMetadata: [String: PlanMetadata] {
        Dictionary(uniqueKeysWithValues: plans.map { plan in
            let resourceID: String? = plan.id == "plan-01" ? "resource-coupon-01" :
                (plan.id == "plan-02" ? "resource-product-01" : nil)
            return (plan.id, PlanMetadata(resourceID: resourceID, createdAt: Self.planSeedDate, updatedAt: Self.planSeedDate))
        })
    }

    var planVersions: [PlanVersionSnapshot] {
        plans.compactMap { plan in
            guard let metadata = planMetadata[plan.id] else { return nil }
            return .init(plan: plan, metadata: metadata,
                         resource: storeResources.first { $0.id == metadata.resourceID },
                         resourceCheckedAt: Self.planReferenceDate,
                         changedAt: metadata.updatedAt, changeSource: .initial, summary: "初始演示内容")
        }
    }

    var planTemplates: [PlanTemplate] {
        [.init(id: "plan-template-care", title: "关怀与回购 · 模拟 AI 模板",
               content: .init(purpose: .repurchase, customerStage: .purchased,
                              message: "最近的使用体验还好吗？如需补货或了解使用方法，欢迎告诉我们。为你准备了一份回购礼遇。",
                              resourceID: "resource-coupon-01"))]
    }

    var planSuggestions: [PlanSuggestion] {
        guard let plan = plans.first(where: { $0.id == "plan-01" }) else { return [] }
        var proposed = PlanContent(plan: plan, resourceID: "resource-coupon-01")
        proposed.message = "最近使用体验如何？欢迎告诉我们你的感受。如有补货需要，可以了解这份回购礼遇。"
        var invalid = proposed
        invalid.resourceID = "resource-expired-01"
        return [
            .init(id: "plan-suggestion-01", planID: plan.id, baseVersion: 1, proposed: proposed,
                  evidenceStart: analytics.startDate, evidenceEnd: analytics.endDate,
                  reason: "历史样本中两方案表现不同；建议只调整关怀表达，继续在相同条件下验证。",
                  expectedImpact: "表达更清晰；不能据单次转化率推断永久最优或保证成交。"),
            .init(id: "plan-suggestion-expired", planID: plan.id, baseVersion: 1, proposed: invalid,
                  evidenceStart: analytics.startDate, evidenceEnd: analytics.endDate,
                  reason: "失效资源校验样本。", expectedImpact: "引用资源已结束，此建议不可直接采纳。")
        ]
    }

    var touchRules: [TouchRule] {
        guard let first = plans.first else { return [] }
        let birthday = TouchRuleConfiguration(primaryPlanID: first.id)
        var followUp = birthday
        followUp.kind = .followUp
        if let second = plans.dropFirst().first {
            followUp.secondaryPlanID = second.id
            followUp.primaryPercentage = Self.planRecommendedPrimaryPercentage
        }
        return [.init(id: "rule-birthday-01", number: 1, revision: 1, configuration: birthday, updatedAt: Self.planSeedDate),
                .init(id: "rule-followup-01", number: 2, revision: 1, configuration: followUp, updatedAt: Self.planSeedDate)]
    }

    var planRuleRanges: [PlanRuleRange] {
        [.init(kind: .birthday, period: nil, audienceID: "audience-01", expectedReach: 24,
               summary: "预设的当天生日范围，已去重 24 人；生日来自本地样本假设。"),
         .init(kind: .followUp, period: .threeMonths, audienceID: "audience-01", expectedReach: 120,
               summary: "预设的最近购买满三个月范围，已去重 120 人；不是实时订单计算。"),
         .init(kind: .followUp, period: .sixMonths, audienceID: "audience-01", expectedReach: 0,
               summary: "六个月周期的无匹配边界样本，预计 0 人。")]
    }
}
