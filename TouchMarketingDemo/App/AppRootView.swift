import SwiftUI

struct AppRootView: View {
    @State private var selectedTab: AppTab = .audience
    @State private var session = DemoSession()
    @State private var confirmReset = false

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    moduleHome(for: tab)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Menu {
                                    Button("重置演示", role: .destructive) { confirmReset = true }
                                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("演示工具") }
                            }
                        }
                }
                .tabItem { Label(tab.title, systemImage: tab.symbol) }
                .tag(tab)
            }
        }
        .environment(session)
        .environment(\.planSession, session)
        .environment(\.analyticsIntegration, AnalyticsIntegration(
            statistics: session.analyticsStatistics, resetGeneration: session.resetGeneration,
            loadStatistics: { session.loadAnalyticsStatistics(batchID: $0) }))
        .id(session.resetGeneration)
        .tint(DemoTheme.ColorToken.primaryText)
        .confirmationDialog("重置所有演示数据？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("重置所有模块", role: .destructive) { selectedTab = .audience; session.reset() }
            Button("取消", role: .cancel) { }
        } message: { Text("清除本次新增、编辑、版本、建议处理及页面草稿，恢复统一初始样本。") }
    }

    @ViewBuilder
    private func moduleHome(for tab: AppTab) -> some View {
        switch tab {
        case .audience: AudienceHomeView(store: session.store, session: session)
        case .plan: PlanHomeView(store: session.store)
        case .approval: ApprovalHomeView(store: session.store)
        case .analytics: AnalyticsHomeView(store: session.store)
        }
    }
}

#Preview { AppRootView().preferredColorScheme(.light) }
