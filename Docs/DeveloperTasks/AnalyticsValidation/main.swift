import Foundation

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else { fatalError("FAIL: \(label)") }
    checks += 1
    print("PASS: \(label)")
}
func close(_ actual: Double?, _ expected: Double) -> Bool { actual.map { abs($0 - expected) < 0.0000001 } ?? false }
let seed = MockDataStore.demo
let defaultQuery = AnalyticsSelection().query
let week = AnalyticsFixtures.historical(defaultQuery, store: seed)
expect(AnalyticsPeriod.week.range.label == "2026/10/05—2026/10/11", "D03 seven-day bounds")
expect(AnalyticsPeriod.month.range.label == "2026/09/12—2026/10/11", "D03 thirty-day bounds")
expect(AnalyticsPeriod.quarter.range.label == "2026/07/12—2026/10/11", "D03 calendar-month bounds")
expect(AnalyticsPeriod.week.range.contains(AnalyticsDateRange.date(2026, 10, 5)), "start included")
expect(!AnalyticsPeriod.week.range.contains(AnalyticsDateRange.date(2026, 10, 12)), "end excluded")
expect(week.totals == AnalyticsValues(reached: 2000, converted: 168, orders: 196, cents: 2_940_000), "D01 historical totals")
expect(close(week.totals.conversion, 0.084), "D02 total conversion recomputed")
expect(close(week.performances[0].values.conversion, 0.06), "D02 plan01 conversion")
expect(close(week.performances[1].values.conversion, 132.0 / 1400), "D02 plan02 conversion")
expect(close(week.totals.averageOrderCents, 15000), "D09 average order ¥150")
expect(close(week.totals.revenuePerReachCents, 1470), "D09 per reach ¥14.70")
expect(close(week.totals.ordersPerReach, 0.098), "D09 order yield 0.098")
let month = AnalyticsFixtures.historical(.init(period: .month, audienceID: "audience-01", planIDs: []), store: seed)
let quarter = AnalyticsFixtures.historical(.init(period: .quarter, audienceID: "audience-01", planIDs: []), store: seed)
expect(month.totals.reached == 2300 && quarter.totals.reached == 2500, "D03 additional dated samples change results")
expect(month.points.count == 15 && quarter.points.count == 16, "D03 trends change with period")
var original = AnalyticsSelection()
var draft = original
expect(!draft.toggle("plan-03"), "D05 third plan rejected")
expect(draft.toggle("plan-02") && draft.toggle("plan-03"), "D05 replacement supported")
expect(original.query == defaultQuery, "D04 discarded draft leaves selection unchanged")
original = draft
expect(original.query == draft.query, "D04 application replaces entire query")
let single = AnalyticsFixtures.historical(.init(period: .week, audienceID: "audience-01", planIDs: ["plan-01"]), store: seed)
expect(single.performances.count == 1 && single.points.count == 7 && single.totals.reached == 600, "D05 single-series summary/trend/comparison")
let empty = AnalyticsFixtures.historical(.init(period: .week, audienceID: "audience-02", planIDs: ["plan-02"]), store: seed)
expect(empty.completion == .noMatch && empty.points.isEmpty && empty.totals.reached == nil, "D06 no previous data leakage")
expect(!AnalyticsQuery(period: .week, audienceID: nil, planIDs: ["plan-01", "plan-01"]).valid, "duplicate IDs invalid")
let all = AnalyticsFixtures.historical(.init(period: .week, audienceID: nil, planIDs: []), store: seed)
expect(all.totals == AnalyticsValues(reached: 2700, converted: 228, orders: 296, cents: 4_440_000), "D11 overlap-adjusted union")
expect(close(all.totals.conversion, 228.0 / 2700), "D11 union conversion 8.44%")
expect(AnalyticsFixtures.planTotals(all, planID: "plan-01").reached == 1300, "D11 same-plan cross-version union")
expect(Set(all.performances.map(\.id)).count == all.performances.count, "D12 unique batch/plan/version IDs")
expect(Set(all.performances.filter { $0.planID == "plan-01" }.map(\.planVersion)) == [1, 2], "D12 mixed versions retained")
let editedPlan = MarketingPlan(id: "plan-01", number: 1, purpose: .repurchase, customerStage: .purchased, version: 2,
                               message: "new latest content", resourceSummary: "new latest resource", source: .manual, audienceIDs: ["audience-01"])
let editedStore = MockDataStore(audiences: seed.audiences, plans: [editedPlan, seed.plans[1]], approvalTasks: seed.approvalTasks, analytics: seed.analytics)
let historicalAfterEdit = AnalyticsFixtures.historical(defaultQuery, store: editedStore)
expect(historicalAfterEdit.performances[0].planVersion == 1 && !(historicalAfterEdit.performances[0].sourceSnapshot ?? "").contains("new latest"), "D12 latest V2 does not overwrite V1 snapshot")
let zeroReach = AnalyticsFixtures.boundary(.zeroReach)
let zeroSales = AnalyticsFixtures.boundary(.zeroSales)
let pending = AnalyticsFixtures.boundary(.pending)
expect(zeroReach.totals.conversion == nil && AnalyticsMetric.conversion.display(zeroReach.totals, completion: .complete) == "—", "D10 zero denominator")
expect(zeroSales.totals.conversion == 0 && AnalyticsMetric.conversion.display(zeroSales.totals, completion: .complete) == "0.00%", "D10 observed zero sales")
expect(pending.totals.converted == nil && AnalyticsMetric.converted.display(pending.totals, completion: .pending) == "统计中", "D10 unknown is not zero")
let day = week.points.first!
expect(AnalyticsMetric.chartMetrics.map { $0.value(day.values)! } == [60, 3, 4, 600, 5], "D07 five metrics use independent units/values")
expect(close(day.values.conversion, 3.0 / 60), "D08 date rate uses date operands")
let missing = AnalyticsFixtures.boundary(.missing)
let reads = AnalyticsChartReading.readings(missing.points, metric: .reached)
expect(reads.count == 2 && Set(reads.map(\.segment)).count == 2, "D16 missing observation splits line segments")
expect(AnalyticsChartReading.readings(AnalyticsFixtures.boundary(.noPoints).points, metric: .reached).isEmpty, "D16 empty trend")
expect(AnalyticsChartReading.readings(zeroSales.points, metric: .conversion).count == 1, "D16 single observed zero point")
var ledger = AnalyticsBatchStatistics()
expect(ledger.receive(AnalyticsFixtures.callback(retried: false)), "D13 adapter accepts cumulative callback fixture")
expect(ledger.report(batchID: "fixture-new-batch", query: defaultQuery).totals.reached == 1850, "D13 actual successes instead of allocated counts")
expect(ledger.report(batchID: "fixture-new-batch", query: defaultQuery).totals.converted == nil, "D13 new callback starts pending")
expect(!ledger.load(batchID: "fixture-new-batch"), "D14 unmatched incomplete success scope stays pending")
expect(ledger.receive(AnalyticsFixtures.callback(retried: true)), "D15 retry revision accepted")
expect(ledger.report(batchID: "fixture-new-batch", query: defaultQuery).totals.reached == 2000 && ledger.batches.count == 1, "D15 unique total replaced, not added")
expect(!ledger.receive(AnalyticsFixtures.callback(retried: false)), "D15 stale retry callback ignored")
expect(ledger.load(batchID: "fixture-new-batch"), "D14 matching 50/50 result loaded")
let loaded = ledger
expect(!ledger.load(batchID: "fixture-new-batch") && ledger == loaded && ledger.loaded.count == 1, "D14 duplicate load is idempotent")
expect(!ledger.receive(AnalyticsFixtures.callback(retried: true)) && ledger == loaded, "D15 duplicate revision preserves loaded statistics")
let result = ledger.report(batchID: "fixture-new-batch", query: defaultQuery)
expect(result.totals == AnalyticsValues(reached: 2000, converted: 130, orders: 150, cents: 2_250_000), "D14 simulation does not copy history")
expect(ledger.report(batchID: "fixture-new-batch", query: .init(period: .week, audienceID: "audience-02", planIDs: [])).completion == .noMatch, "D13 batch respects audience filter")
expect(ledger.report(batchID: "fixture-new-batch", query: .init(period: .week, audienceID: nil, planIDs: ["plan-01"])).totals.converted == 50, "D14 filtered batch statistics")
let wrongVersion = AnalyticsBatchInput(id: "v2-batch", taskID: "task-x", audienceID: "audience-01", audienceNumber: 1,
                                      audienceVersion: 2, businessDate: AnalyticsDateRange.date(2026, 10, 11), revision: 1,
                                      groups: AnalyticsFixtures.callback(retried: true).groups)
expect(ledger.receive(wrongVersion) && !ledger.load(batchID: "v2-batch"), "D14 version mismatch not loaded")
let beforeInvalid = ledger
let changedVersion = AnalyticsBatchInput(id: "fixture-new-batch", taskID: "fixture-task", audienceID: "audience-01", audienceNumber: 1,
                                        audienceVersion: 2, businessDate: AnalyticsDateRange.date(2026, 10, 11), revision: 3,
                                        groups: AnalyticsFixtures.callback(retried: true).groups)
expect(!ledger.receive(changedVersion) && ledger == beforeInvalid, "D15 retry cannot alter frozen snapshot")
let future = AnalyticsBatchInput(id: "future", taskID: "future-task", audienceID: "audience-01", audienceNumber: 1,
                                audienceVersion: 1, businessDate: AnalyticsDateRange.date(2026, 10, 12), revision: 1,
                                groups: AnalyticsFixtures.callback(retried: true).groups)
expect(ledger.receive(future) && ledger.report(batchID: "future", query: defaultQuery).completion == .noMatch, "D03 new batch excluded at end boundary")
let invalidGroups = AnalyticsBatchInput(id: "invalid", taskID: "x", audienceID: "audience-01", audienceNumber: 1,
                                       audienceVersion: 1, businessDate: AnalyticsDateRange.date(2026, 10, 11), revision: 1,
                                       groups: [AnalyticsFixtures.callback(retried: true).groups[0], AnalyticsFixtures.callback(retried: true).groups[0]])
expect(!ledger.receive(invalidGroups), "invalid duplicate group input rejected")
let invalidHistory = AnalyticsBatchInput(id: "task-history-02", taskID: "x", audienceID: "audience-01", audienceNumber: 1,
                                        audienceVersion: 1, businessDate: AnalyticsDateRange.date(2026, 10, 11), revision: 1,
                                        groups: AnalyticsFixtures.callback(retried: true).groups)
expect(!ledger.receive(invalidHistory), "historical IDs protected from incoming callbacks")
expect(!AnalyticsValues(reached: 10, converted: 11, orders: 11, cents: 0).valid, "converted count cannot exceed reached")
expect(!AnalyticsValues(reached: -1, converted: nil, orders: nil, cents: nil).valid, "negative counts invalid")
expect(AnalyticsValues.disjointSum([pending.totals, zeroSales.totals]).converted == nil, "unknown constituent cannot produce false zero union")
for planID in ["plan-01", "plan-02"] {
    let points = week.points.filter { $0.planID == planID }
    let record = week.performances.first { $0.planID == planID }!
    expect(points.reduce(0) { $0 + ($1.values.cents ?? 0) } == record.values.cents, "daily orders/money agree with main batch \(planID)")
}
expect(AnalyticsFixtures.select(week, query: .init(period: .week, audienceID: nil, planIDs: ["plan-01", "plan-02", "plan-03"]), disjoint: true).completion == .noMatch, "direct adapter query also rejects three plans")
ledger.reset()
expect(ledger.batches.isEmpty && ledger.loaded.isEmpty, "D18 domain reset clears new data; root integration still required")
expect(AnalyticsFixtures.historical(defaultQuery, store: seed) == week, "D14/D18 history unaffected by new batches and reset")
print("\(checks) meaningful analytics checks passed. A/C UI integration is NOT certified by these fixture checks.")
