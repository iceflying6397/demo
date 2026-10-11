import SwiftUI

struct PlanHomeView: View {
    let store: MockDataStore
    @Environment(\.planSession) private var session
    @State private var query = ""
    @State private var purpose: PlanPurpose?
    @State private var stage: CustomerStage?
    private var context: PlanContext { .init(store: store, session: session) }
    private var filteredPlans: [MarketingPlan] {
        context.plans.filter {
            PlanPresentation.matchesNumber($0, query: query) &&
            (purpose == nil || $0.purpose == purpose) && (stage == nil || $0.customerStage == stage)
        }.sorted { $0.number < $1.number }
    }
    var body: some View {
        DemoPage {
            DemoIntro(description: "按目的与适用客户查看营销方案。")
            DemoCard {
                TextField("搜索编号，如 01 或方案 01", text: $query)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("plan.search")
                Picker("目的", selection: $purpose) {
                    Text("全部目的").tag(Optional<PlanPurpose>.none)
                    ForEach(PlanPurpose.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                Picker("适用客户", selection: $stage) {
                    Text("全部客户").tag(Optional<CustomerStage>.none)
                    ForEach(CustomerStage.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                if !query.isEmpty || purpose != nil || stage != nil {
                    Button("清除筛选", action: clearFilters).buttonStyle(DemoSecondaryButtonStyle())
                }
            }
            NavigationLink("新建方案") { PlanEditView(store: store, plan: nil, resourceID: nil) }
                .buttonStyle(DemoPrimaryButtonStyle()).accessibilityIdentifier("plan.create")
            NavigationLink("触达规则") { PlanRuleListView(store: store) }.buttonStyle(DemoSecondaryButtonStyle())
            Text("\(filteredPlans.count) 套方案").font(DemoTheme.Typography.title)
            if filteredPlans.isEmpty {
                DemoEmptyState(title: "没有符合条件的方案", message: "试试其他编号、目的或适用客户。")
                Button("显示全部方案", action: clearFilters).buttonStyle(DemoSecondaryButtonStyle())
            }
            ForEach(filteredPlans) { plan in
                NavigationLink {
                    PlanDetailView(plan: plan, store: store)
                } label: {
                    DemoCard {
                        HStack {
                            Text(plan.displayName).font(DemoTheme.Typography.heading)
                            Spacer()
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }
                        DemoValueRow(title: "目的", value: plan.purpose.rawValue)
                        DemoValueRow(title: "适用客户", value: plan.customerStage.rawValue)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plan.\(plan.id)")
            }
        }
        .navigationTitle("方案")
    }

    private func clearFilters() { query = ""; purpose = nil; stage = nil }
}
