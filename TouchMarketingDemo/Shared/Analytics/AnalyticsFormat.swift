import Foundation

extension DemoFormat {
    static func analyticsMoney(cents: Double?) -> String {
        cents.map { ($0 / 100).formatted(.currency(code: "CNY").locale(locale).precision(.fractionLength(2))) } ?? "—"
    }
}
