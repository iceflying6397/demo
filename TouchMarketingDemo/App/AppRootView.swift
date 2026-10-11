import SwiftUI

struct AppRootView: View {
    @State private var selectedTab: AppTab = .audience
    @State private var session = DemoSession(seed: .demo)
    private let store = MockDataStore.demo

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    moduleHome(for: tab)
                }
                .tabItem { Label(tab.title, systemImage: tab.symbol) }
                .tag(tab)
            }
        }
        .tint(DemoTheme.ColorToken.primaryText)
        .environment(session)
    }

    @ViewBuilder
    private func moduleHome(for tab: AppTab) -> some View {
        switch tab {
        case .audience: AudienceHomeView(store: store)
        case .plan: PlanHomeView(store: store)
        case .approval: ApprovalHomeView(store: store)
        case .analytics: AnalyticsHomeView(store: store)
        }
    }
}

#Preview { AppRootView().preferredColorScheme(.light) }
