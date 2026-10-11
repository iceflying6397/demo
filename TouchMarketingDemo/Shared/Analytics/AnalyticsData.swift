import Foundation

/// D 提供的独立公共增补。A 可将这些值类型纳入唯一 DemoSession；不建立第二个 store。
enum AnalyticsPeriod: String, CaseIterable, Identifiable {
    case week = "近7日", month = "近30日", quarter = "近3个月"
    var id: Self { self }
    var range: AnalyticsDateRange {
        let calendar = AnalyticsDateRange.calendar
        let end = AnalyticsDateRange.date(2026, 10, 12)
        let start: Date
        switch self {
        case .week: start = calendar.date(byAdding: .day, value: -7, to: end)!
        case .month: start = calendar.date(byAdding: .day, value: -30, to: end)!
        case .quarter: start = calendar.date(byAdding: .month, value: -3, to: end)!
        }
        return AnalyticsDateRange(start: start, endExclusive: end)
    }
}

struct AnalyticsDateRange: Hashable {
    let start: Date
    let endExclusive: Date
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        // Only deterministic seed dates call this helper; incoming batch dates use Date directly.
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    var displayEnd: Date { Self.calendar.date(byAdding: .day, value: -1, to: endExclusive)! }
    var label: String { DemoFormat.dateRange(start: start, end: displayEnd) }
    func contains(_ date: Date) -> Bool { date >= start && date < endExclusive }
}

/// nil 是未知，0 是已统计零值；金额始终存分。
struct AnalyticsValues: Hashable {
    let reached: Int?
    let converted: Int?
    let orders: Int?
    let cents: Int?
    init(reached: Int?, converted: Int?, orders: Int?, cents: Int?) {
        self.reached = reached; self.converted = converted; self.orders = orders; self.cents = cents
    }
    init(_ metrics: MarketingMetrics) {
        self.init(reached: metrics.reachedCustomers, converted: metrics.convertedCustomers,
                  orders: metrics.orderCount, cents: metrics.revenueInCents)
    }
    var conversion: Double? { ratio(converted, reached) }
    var averageOrderCents: Double? { ratio(cents, orders) }
    var revenuePerReachCents: Double? { ratio(cents, reached) }
    var ordersPerReach: Double? { ratio(orders, reached) }
    private func ratio(_ numerator: Int?, _ denominator: Int?) -> Double? {
        guard let numerator, let denominator, denominator > 0 else { return nil }
        return Double(numerator) / Double(denominator)
    }
    var complete: Bool { reached != nil && converted != nil && orders != nil && cents != nil }
    var valid: Bool {
        [reached, converted, orders, cents].compactMap { $0 }.allSatisfy { $0 >= 0 }
        && (converted == nil || reached == nil || converted! <= reached!)
        && (orders == nil || converted == nil || orders! >= converted!)
    }
    /// Only use where Shared fixture explicitly guarantees mutually exclusive customers AND orders.
    static func disjointSum(_ values: [Self]) -> Self {
        func sum(_ key: KeyPath<Self, Int?>) -> Int? {
            let known = values.compactMap { $0[keyPath: key] }
            return known.count == values.count ? known.reduce(0, +) : nil
        }
        return Self(reached: sum(\.reached), converted: sum(\.converted), orders: sum(\.orders), cents: sum(\.cents))
    }
}

enum AnalyticsCompletion: String {
    case complete = "已统计", pending = "统计中", partial = "部分缺失", noMatch = "无匹配数据"
}

struct AnalyticsPerformance: Identifiable, Hashable {
    let batchID: String
    let planID: String
    let planNumber: Int
    let planVersion: Int
    let audienceID: String
    let audienceNumber: Int
    let audienceVersion: Int
    let percentage: Int
    let businessDate: Date
    let sourceSnapshot: String?
    let values: AnalyticsValues
    var id: String { "\(batchID)|\(planID)|v\(planVersion)" }
    var planName: String { DemoFormat.numbered("方案", planNumber) }
    var audienceName: String { DemoFormat.numbered("人群", audienceNumber) }
}

struct AnalyticsTrendPoint: Identifiable, Hashable {
    let seriesID: String
    let planID: String
    let planNumber: Int
    let date: Date
    let values: AnalyticsValues
    var id: String { "\(seriesID)|\(date.timeIntervalSince1970)" }
}

struct AnalyticsQuery: Hashable {
    let period: AnalyticsPeriod
    let audienceID: String? // nil = 全部
    let planIDs: [String]   // empty = 不指定
    var valid: Bool { planIDs.count <= 2 && Set(planIDs).count == planIDs.count }
}

struct AnalyticsReport: Hashable {
    let query: AnalyticsQuery
    let performances: [AnalyticsPerformance]
    let totals: AnalyticsValues
    let points: [AnalyticsTrendPoint]
    let completion: AnalyticsCompletion
    let deduplication: String
    let explanation: String
    var isSameGroup: Bool {
        Set(performances.map(\.batchID)).count == 1 && Set(performances.map(\.audienceID)).count == 1
    }
    static func empty(_ query: AnalyticsQuery, _ reason: String) -> Self {
        Self(query: query, performances: [], totals: .init(reached: nil, converted: nil, orders: nil, cents: nil),
             points: [], completion: .noMatch, deduplication: "未提供联合去重摘要", explanation: reason)
    }
}

/// C -> D: cumulative unique success counts, not counts for each attempt. Frozen at confirmation.
struct AnalyticsBatchInput: Hashable, Identifiable {
    struct Group: Hashable {
        let planID: String
        let planNumber: Int
        let planVersion: Int
        let percentage: Int
        let allocated: Int
        let uniqueSucceeded: Int
        let sourceSnapshot: String?
    }
    let id: String // execution batch ID; must differ from historical task ID
    let taskID: String
    let audienceID: String
    let audienceNumber: Int
    let audienceVersion: Int
    let businessDate: Date
    let revision: Int // monotonic execution revision, including retry callbacks
    let groups: [Group]
    var valid: Bool {
        !id.isEmpty && !taskID.isEmpty && !id.hasPrefix("task-history-") && audienceNumber > 0 && audienceVersion > 0 && revision >= 0
        && (1...2).contains(groups.count) && Set(groups.map(\.planID)).count == groups.count
        && groups.reduce(0) { $0 + $1.percentage } == 100
        && groups.allSatisfy { !$0.planID.isEmpty && $0.planNumber > 0 && $0.planVersion > 0 && (1...100).contains($0.percentage)
            && $0.allocated >= 0 && (0...$0.allocated).contains($0.uniqueSucceeded) }
    }
    /// Full configuration key: never attach 30/70 history to a new 50/50 send.
    var configurationKey: String {
        ([audienceID, "v\(audienceVersion)", "\(businessDate.timeIntervalSince1970)"] + groups.sorted { $0.planID < $1.planID }.map {
            "\($0.planID)|v\($0.planVersion)|\($0.percentage)|\($0.allocated)|\($0.uniqueSucceeded)"
        }).joined(separator: ":")
    }
}

/// Value reducer to be owned by A's session. No global singleton, sender or timers.
struct AnalyticsBatchStatistics: Equatable {
    private(set) var batches: [String: AnalyticsBatchInput] = [:]
    private(set) var loaded: [String: AnalyticsReport] = [:]
    @discardableResult mutating func receive(_ input: AnalyticsBatchInput) -> Bool {
        guard input.valid else { return false }
        if let old = batches[input.id] {
            guard input.revision > old.revision, input.taskID == old.taskID,
                  input.audienceID == old.audienceID, input.audienceNumber == old.audienceNumber, input.audienceVersion == old.audienceVersion,
                  input.businessDate == old.businessDate, input.groups.count == old.groups.count else { return false }
            for group in input.groups {
                guard let previous = old.groups.first(where: { $0.planID == group.planID }),
                      group.planNumber == previous.planNumber, group.planVersion == previous.planVersion, group.percentage == previous.percentage,
                      group.allocated == previous.allocated, group.sourceSnapshot == previous.sourceSnapshot,
                      group.uniqueSucceeded >= previous.uniqueSucceeded else { return false }
            }
        }
        batches[input.id] = input
        // A retry changes successful scope: conversion results must be explicitly reloaded for that scope.
        loaded.removeValue(forKey: input.id)
        return true
    }
    @discardableResult mutating func load(batchID: String) -> Bool {
        guard let input = batches[batchID], loaded[batchID] == nil,
              let report = AnalyticsFixtures.matchedStatistics(input) else { return false }
        loaded[batchID] = report
        return true
    }
    mutating func reset() { self = Self() }
    func report(batchID: String, query: AnalyticsQuery) -> AnalyticsReport {
        guard query.valid, let batch = batches[batchID], query.period.range.contains(batch.businessDate),
              query.audienceID == nil || query.audienceID == batch.audienceID else {
            return .empty(query, "本批次不在所选业务日期或人群范围内。")
        }
        let result = loaded[batchID] ?? AnalyticsFixtures.pending(batch)
        return AnalyticsFixtures.select(result, query: query, disjoint: true)
    }
}
