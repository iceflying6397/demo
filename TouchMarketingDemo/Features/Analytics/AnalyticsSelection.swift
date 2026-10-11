import SwiftUI

struct AnalyticsSelection: Equatable {
    var period: AnalyticsPeriod = .week
    var audienceID: String? = "audience-01"
    var planIDs: [String] = ["plan-01", "plan-02"]
    var query: AnalyticsQuery { .init(period: period, audienceID: audienceID, planIDs: planIDs.sorted()) }
    mutating func toggle(_ id: String) -> Bool {
        if planIDs.contains(id) { planIDs.removeAll { $0 == id }; return true }
        guard planIDs.count < 2 else { return false }
        planIDs.append(id); return true
    }
}

enum AnalyticsMetric: String, CaseIterable, Identifiable {
    case reached = "触达人数", converted = "成交人数", orders = "订单数", revenue = "成交金额", conversion = "成交转化率"
    case averageOrder = "客单价", revenuePerReach = "触达人均成交金额", ordersPerReach = "每触达客户订单产出"
    var id: Self { self }
    static let chartMetrics: [Self] = [.reached, .converted, .orders, .revenue, .conversion]
    var unit: String {
        switch self {
        case .reached, .converted: "人"
        case .orders: "单"
        case .revenue: "元"
        case .conversion: "%"
        case .averageOrder: "元／单"
        case .revenuePerReach: "元／人"
        case .ordersPerReach: "单／人"
        }
    }
    var formula: String {
        switch self {
        case .reached: "统计范围内成功触达的唯一客户数"
        case .converted: "同口径去重支付客户数"
        case .orders: "同口径有效支付订单数"
        case .revenue: "对应有效订单的成交金额（人民币分÷100）"
        case .conversion: "成交人数 ÷ 触达人数 × 100%"
        case .averageOrder: "成交金额 ÷ 订单数"
        case .revenuePerReach: "成交金额 ÷ 触达人数"
        case .ordersPerReach: "订单数 ÷ 触达人数（可能大于1）"
        }
    }
    func value(_ values: AnalyticsValues) -> Double? {
        switch self {
        case .reached: values.reached.map(Double.init)
        case .converted: values.converted.map(Double.init)
        case .orders: values.orders.map(Double.init)
        case .revenue: values.cents.map { Double($0) / 100 }
        case .conversion: values.conversion.map { $0 * 100 }
        case .averageOrder: values.averageOrderCents.map { $0 / 100 }
        case .revenuePerReach: values.revenuePerReachCents.map { $0 / 100 }
        case .ordersPerReach: values.ordersPerReach
        }
    }
    func display(_ values: AnalyticsValues, completion: AnalyticsCompletion) -> String {
        if value(values) == nil {
            if [.conversion, .averageOrder, .revenuePerReach, .ordersPerReach].contains(self) {
                if self == .averageOrder && values.orders == 0 { return "—" }
                if self != .averageOrder && values.reached == 0 { return "—" }
            }
            return completion == .pending ? "统计中" : "—（未知）"
        }
        switch self {
        case .reached: return "\(DemoFormat.count(values.reached!)) 人"
        case .converted: return "\(DemoFormat.count(values.converted!)) 人"
        case .orders: return "\(DemoFormat.count(values.orders!)) 单"
        case .revenue: return DemoFormat.currency(cents: values.cents!)
        case .conversion: return DemoFormat.percent(values.conversion)
        case .averageOrder: return DemoFormat.analyticsMoney(cents: values.averageOrderCents) + "／单"
        case .revenuePerReach: return DemoFormat.analyticsMoney(cents: values.revenuePerReachCents) + "／人"
        case .ordersPerReach: return values.ordersPerReach!.formatted(.number.locale(DemoFormat.locale).precision(.fractionLength(3))) + " 单／人"
        }
    }
    func operands(_ values: AnalyticsValues) -> (String, String) {
        func count(_ value: Int?) -> String { value.map(DemoFormat.count) ?? "未知" }
        switch self {
        case .conversion: return (count(values.converted) + " 人", count(values.reached) + " 人")
        case .averageOrder: return (values.cents.map(DemoFormat.currency) ?? "未知", count(values.orders) + " 单")
        case .revenuePerReach: return (values.cents.map(DemoFormat.currency) ?? "未知", count(values.reached) + " 人")
        case .ordersPerReach: return (count(values.orders) + " 单", count(values.reached) + " 人")
        default: return (display(values, completion: .partial), "不适用（基础指标）")
        }
    }
}
