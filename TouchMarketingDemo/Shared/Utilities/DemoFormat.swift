import Foundation

enum DemoFormat {
    static let locale = Locale(identifier: "zh_CN")
    static func numbered(_ prefix: String, _ number: Int) -> String {
        "\(prefix) \(String(format: "%02d", number))"
    }
    static func count(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }
    static func currency(cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: "CNY").locale(locale).precision(.fractionLength(0...2)))
    }
    static func percent(_ value: Double?) -> String {
        value.map { $0.formatted(.percent.locale(locale).precision(.fractionLength(2))) } ?? "—"
    }
    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
    static func dateRange(start: Date, end: Date) -> String {
        "\(day(start))—\(day(end))"
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
}
