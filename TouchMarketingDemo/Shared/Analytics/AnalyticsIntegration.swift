import SwiftUI

/// A injects a value snapshot of its observed session and a mutation closure; D never owns a second session.
struct AnalyticsIntegration {
    var statistics: AnalyticsBatchStatistics
    var resetGeneration: Int
    var loadStatistics: (String) -> Bool
}
private struct AnalyticsIntegrationKey: EnvironmentKey {
    static let defaultValue: AnalyticsIntegration? = nil
}
extension EnvironmentValues {
    var analyticsIntegration: AnalyticsIntegration? {
        get { self[AnalyticsIntegrationKey.self] }
        set { self[AnalyticsIntegrationKey.self] = newValue }
    }
}
