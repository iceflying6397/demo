import Foundation

/// Unified deterministic fixtures. All customer unions below are supplied metadata, not a real dedup engine.
enum AnalyticsFixtures {
    static let historySnapshots = [
        "plan-01": "V1 · 复购促进 · 已购客户\n最近使用体验如何？为你准备了一份回购礼遇，欢迎了解适合你的补货选择。\n店铺已有优惠券 · 示例资源",
        "plan-02": "V1 · 复购促进 · 已购客户\n感谢你的支持。这里有一份产品关怀与回购推荐，希望继续为你提供合适的选择。\n店铺已有商品推荐 · 示例资源"
    ]
    static func performance(batch: String, plan: Int, version: Int = 1, audience: Int = 1,
                            percentage: Int, date: Date, values: AnalyticsValues, snapshot: String? = nil) -> AnalyticsPerformance {
        AnalyticsPerformance(batchID: batch, planID: String(format: "plan-%02d", plan), planNumber: plan,
                             planVersion: version, audienceID: String(format: "audience-%02d", audience),
                             audienceNumber: audience, audienceVersion: 1, percentage: percentage,
                             businessDate: date, sourceSnapshot: snapshot, values: values)
    }
    static func historical(_ query: AnalyticsQuery, store: MockDataStore) -> AnalyticsReport {
        guard query.valid else { return .empty(query, "最多选择两套不同方案。") }
        guard query.audienceID == nil || ["audience-01", "audience-02"].contains(query.audienceID!) else {
            return .empty(query, "该人群暂无模拟统计。")
        }
        guard query.planIDs.allSatisfy({ ["plan-01", "plan-02"].contains($0) }) else {
            return .empty(query, "所选方案在该范围没有统计样本，未沿用上一范围。")
        }
        let main = store.analytics.performances.map { item in
            performance(batch: store.analytics.deliveryTaskID, plan: item.planID == "plan-01" ? 1 : 2,
                        version: item.planVersion, percentage: item.planID == "plan-01" ? 30 : 70,
                        date: AnalyticsDateRange.date(2026, 10, 5), values: AnalyticsValues(item.metrics),
                        snapshot: historySnapshots[item.planID])
        }
        let other = performance(batch: "task-history-02", plan: 1, version: 2, audience: 2, percentage: 100,
                                date: AnalyticsDateRange.date(2026, 10, 10),
                                values: .init(reached: 1000, converted: 90, orders: 100, cents: 1_500_000),
                                snapshot: "V2 · 复购促进 · 已购客户\n跨任务固定话术与店铺资源快照；与 V1 的条件不同。")
        let month = performance(batch: "task-history-03", plan: 1, percentage: 100,
                                date: AnalyticsDateRange.date(2026, 9, 20),
                                values: .init(reached: 300, converted: 18, orders: 21, cents: 315_000),
                                snapshot: historySnapshots["plan-01"])
        let quarter = performance(batch: "task-history-04", plan: 2, version: 2, percentage: 100,
                                  date: AnalyticsDateRange.date(2026, 8, 10),
                                  values: .init(reached: 200, converted: 20, orders: 25, cents: 375_000),
                                  snapshot: "V2 · 复购促进 · 已购客户\n三个月范围的历史话术与资源固定快照。")
        let records = (main + [other, month, quarter]).filter {
            query.period.range.contains($0.businessDate)
            && (query.audienceID == nil || $0.audienceID == query.audienceID)
            && (query.planIDs.isEmpty || query.planIDs.contains($0.planID))
        }
        guard !records.isEmpty else { return .empty(query, "该人群与方案组合没有匹配的历史样本。") }
        // The only overlapping cohort is history-01/02: 300 reached / 30 converted,
        // all in plan-01. All orders are disjoint; history-03/04 customers are disjoint.
        let hasOverlap = records.contains { $0.batchID == "task-history-01" && $0.planID == "plan-01" }
            && records.contains { $0.batchID == "task-history-02" }
        let sum = AnalyticsValues.disjointSum(records.map(\.values))
        let total = AnalyticsValues(reached: sum.reached.map { $0 - (hasOverlap ? 300 : 0) },
                                    converted: sum.converted.map { $0 - (hasOverlap ? 30 : 0) },
                                    orders: sum.orders, cents: sum.cents)
        var points: [AnalyticsTrendPoint] = []
        for record in records {
            if record.batchID == "task-history-01" {
                let reaches = record.planID == "plan-01" ? [60, 80, 90, 100, 80, 100, 90] : [140, 180, 210, 220, 210, 240, 200]
                let converts = record.planID == "plan-01" ? [3, 4, 5, 6, 5, 7, 6] : [10, 15, 18, 20, 21, 26, 22]
                let orders = record.planID == "plan-01" ? [4, 5, 6, 7, 6, 8, 6] : [12, 17, 21, 23, 24, 30, 27]
                for day in 0..<7 {
                    points.append(.init(seriesID: record.id, planID: record.planID, planNumber: record.planNumber,
                                        date: AnalyticsDateRange.date(2026, 10, 5 + day),
                                        values: .init(reached: reaches[day], converted: converts[day], orders: orders[day], cents: orders[day] * 15_000)))
                }
            } else {
                points.append(.init(seriesID: record.id, planID: record.planID, planNumber: record.planNumber,
                                    date: record.businessDate, values: record.values))
            }
        }
        return AnalyticsReport(query: query, performances: records, totals: total, points: points,
                               completion: .complete,
                               deduplication: hasOverlap ? "预去重联合摘要：触达重叠300人，成交重叠30人；订单互斥。期间客户只计一次，订单与金额无重复。"
                               : "固定样本明确客户与订单互斥；使用期间摘要，不由趋势逐日累加推出人数。",
                               explanation: "本地固定历史样本；按批次业务日期筛选。不同任务／人群／版本的条件可能不同，不能据此认定永久最优方案。")
    }
    static func planTotals(_ report: AnalyticsReport, planID: String) -> AnalyticsValues {
        let records = report.performances.filter { $0.planID == planID }
        let sum = AnalyticsValues.disjointSum(records.map(\.values))
        let overlap = records.contains { $0.batchID == "task-history-01" } && records.contains { $0.batchID == "task-history-02" }
        return .init(reached: sum.reached.map { $0 - (overlap ? 300 : 0) },
                     converted: sum.converted.map { $0 - (overlap ? 30 : 0) }, orders: sum.orders, cents: sum.cents)
    }
    static func pending(_ input: AnalyticsBatchInput) -> AnalyticsReport {
        let records = input.groups.map { group in
            AnalyticsPerformance(batchID: input.id, planID: group.planID, planNumber: group.planNumber,
                                 planVersion: group.planVersion, audienceID: input.audienceID, audienceNumber: input.audienceNumber,
                                 audienceVersion: input.audienceVersion, percentage: group.percentage, businessDate: input.businessDate,
                                 sourceSnapshot: group.sourceSnapshot,
                                 values: .init(reached: group.uniqueSucceeded, converted: nil, orders: nil, cents: nil))
        }
        return batchReport(input, records: records, completion: .pending,
                           explanation: "成功触达为 C 提供的累计唯一人数；成交尚未回流，不复制历史结果。")
    }
    private static func batchReport(_ input: AnalyticsBatchInput, records: [AnalyticsPerformance], completion: AnalyticsCompletion,
                                    explanation: String) -> AnalyticsReport {
        AnalyticsReport(query: .init(period: .week, audienceID: input.audienceID, planIDs: input.groups.map(\.planID)),
                        performances: records, totals: .disjointSum(records.map(\.values)),
                        points: records.map { .init(seriesID: $0.id, planID: $0.planID, planNumber: $0.planNumber, date: $0.businessDate, values: $0.values) },
                        completion: completion, deduplication: "同批次客户互斥；唯一触达是累计快照，重试不累加。", explanation: explanation)
    }
    static func matchedStatistics(_ input: AnalyticsBatchInput) -> AnalyticsReport? {
        // Match complete send configuration, including business date, versions and successful scope.
        // Demo fixture uses 50/50; deliberately does NOT reuse historical 30/70 metrics.
        guard input.valid, input.configurationKey == callback(retried: true).configurationKey else { return nil }
        let records = input.groups.map { group in
            AnalyticsPerformance(batchID: input.id, planID: group.planID, planNumber: group.planNumber, planVersion: group.planVersion,
                                 audienceID: input.audienceID, audienceNumber: input.audienceNumber, audienceVersion: input.audienceVersion,
                                 percentage: group.percentage, businessDate: input.businessDate, sourceSnapshot: group.sourceSnapshot,
                                 values: group.planID == "plan-01" ? .init(reached: 1000, converted: 50, orders: 60, cents: 900_000)
                                 : .init(reached: 1000, converted: 80, orders: 90, cents: 1_350_000))
        }
        return batchReport(input, records: records, completion: .complete, explanation: "已载入匹配50/50配置的确定模拟统计。非真实归因；重复载入不产生第二份结果。")
    }
    static func select(_ report: AnalyticsReport, query: AnalyticsQuery, disjoint: Bool) -> AnalyticsReport {
        guard query.valid else { return .empty(query, "最多选择两套不同方案。") }
        let records = report.performances.filter { query.planIDs.isEmpty || query.planIDs.contains($0.planID) }
        guard !records.isEmpty else { return .empty(query, "所选方案在本批次无匹配统计。") }
        let points = report.points.filter { query.period.range.contains($0.date) && (query.planIDs.isEmpty || query.planIDs.contains($0.planID)) }
        return .init(query: query, performances: records,
                     totals: disjoint ? .disjointSum(records.map(\.values)) : report.totals, points: points,
                     completion: report.completion, deduplication: report.deduplication, explanation: report.explanation)
    }
    enum Boundary: String, CaseIterable, Identifiable {
        case pending = "统计中", zeroSales = "已统计零成交", zeroReach = "零触达", missing = "部分缺失", noPoints = "无趋势点"
        var id: Self { self }
    }
    static func boundary(_ state: Boundary) -> AnalyticsReport {
        let values: AnalyticsValues
        let completion: AnalyticsCompletion
        switch state {
        case .pending: values = .init(reached: 100, converted: nil, orders: nil, cents: nil); completion = .pending
        case .zeroSales: values = .init(reached: 100, converted: 0, orders: 0, cents: 0); completion = .complete
        case .zeroReach: values = .init(reached: 0, converted: 0, orders: 0, cents: 0); completion = .complete
        case .missing: values = .init(reached: 100, converted: 5, orders: nil, cents: nil); completion = .partial
        case .noPoints: values = .init(reached: 100, converted: 5, orders: 6, cents: 90_000); completion = .complete
        }
        let record = performance(batch: "fixture-\(state.id)", plan: 1, percentage: 100,
                                 date: AnalyticsDateRange.date(2026, 10, 11), values: values, snapshot: historySnapshots["plan-01"])
        let points: [AnalyticsTrendPoint] = state == .noPoints ? [] : (state == .missing ? [
            .init(seriesID: record.id, planID: record.planID, planNumber: 1, date: AnalyticsDateRange.date(2026, 10, 5), values: .init(reached: 30, converted: 2, orders: 2, cents: 30_000)),
            .init(seriesID: record.id, planID: record.planID, planNumber: 1, date: AnalyticsDateRange.date(2026, 10, 8), values: .init(reached: nil, converted: nil, orders: nil, cents: nil)),
            .init(seriesID: record.id, planID: record.planID, planNumber: 1, date: AnalyticsDateRange.date(2026, 10, 11), values: .init(reached: 70, converted: 3, orders: nil, cents: nil))
        ] : [.init(seriesID: record.id, planID: record.planID, planNumber: 1, date: record.businessDate, values: values)])
        return .init(query: .init(period: .week, audienceID: "audience-01", planIDs: ["plan-01"]), performances: [record], totals: values,
                     points: points, completion: completion, deduplication: "确定的边界 fixture；不加入历史合计。",
                     explanation: "边界演示 · \(state.rawValue)。未知字段为nil；趋势缺失处断开。")
    }
    static func callback(retried: Bool) -> AnalyticsBatchInput {
        .init(id: "fixture-new-batch", taskID: "fixture-task", audienceID: "audience-01", audienceNumber: 1,
              audienceVersion: 1, businessDate: AnalyticsDateRange.date(2026, 10, 11), revision: retried ? 2 : 1,
              groups: [
                .init(planID: "plan-01", planNumber: 1, planVersion: 1, percentage: 50, allocated: 1000,
                      uniqueSucceeded: retried ? 1000 : 900, sourceSnapshot: historySnapshots["plan-01"]),
                .init(planID: "plan-02", planNumber: 2, planVersion: 1, percentage: 50, allocated: 1000,
                      uniqueSucceeded: retried ? 1000 : 950, sourceSnapshot: historySnapshots["plan-02"])
              ])
    }
}
