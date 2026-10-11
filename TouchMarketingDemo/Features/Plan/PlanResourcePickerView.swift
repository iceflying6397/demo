import SwiftUI

struct PlanResourceContent: View {
    let resource: StoreResource
    let referenceDate: Date
    var historical = false
    var body: some View {
        Text(resource.name).font(DemoTheme.Typography.heading)
        DemoValueRow(title: "资源编号", value: resource.id)
        DemoValueRow(title: "类型", value: resource.kind.rawValue)
        Text(resource.detail).fixedSize(horizontal: false, vertical: true)
        if let amount = resource.amountInCents {
            DemoValueRow(title: resource.kind == .coupon ? "面额" : "价格", value: DemoFormat.currency(cents: amount))
        }
        if let minimum = resource.minimumSpendInCents { DemoValueRow(title: "使用门槛", value: "满 \(DemoFormat.currency(cents: minimum))") }
        if let category = resource.category { DemoValueRow(title: "品类", value: category) }
        DemoValueRow(title: "有效期", value: DemoFormat.dateRange(start: resource.validFrom, end: resource.validThrough))
        DemoValueRow(title: historical ? "快照时状态" : "可用状态",
                     value: resource.invalidReason(on: referenceDate) ?? (resource.kind == .product ? "可售" : "可用"))
        if let url = resource.demoURL {
            Text(verbatim: url).font(DemoTheme.Typography.caption)
            Text("演示链接，未访问店铺").font(DemoTheme.Typography.caption)
        }
    }
}

struct PlanResourcePickerView: View {
    let resources: [StoreResource]
    let referenceDate: Date
    let onConfirm: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ResourceKind
    @State private var selectedID: String?

    init(resources: [StoreResource], referenceDate: Date, selectedID: String?, onConfirm: @escaping (String?) -> Void) {
        self.resources = resources; self.referenceDate = referenceDate; self.onConfirm = onConfirm
        _selectedID = State(initialValue: selectedID)
        _kind = State(initialValue: resources.first { $0.id == selectedID }?.kind ?? .coupon)
    }

    private var selectionValid: Bool {
        guard let selectedID else { return true }
        guard let resource = resources.first(where: { $0.id == selectedID }) else { return false }
        return resource.invalidReason(on: referenceDate) == nil
    }

    var body: some View {
        DemoPage {
            Text("仅选择既有资源；本 Demo 每套方案最多一个主资源，也可不带资源。")
            Picker("资源类型", selection: $kind) {
                ForEach(ResourceKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Button(selectedID == nil ? "✓ 不使用资源" : "不使用资源") { selectedID = nil }
                .buttonStyle(DemoSecondaryButtonStyle())
            ForEach(resources.filter { $0.kind == kind }) { resource in
                DemoCard {
                    PlanResourceContent(resource: resource, referenceDate: referenceDate)
                    if resource.invalidReason(on: referenceDate) == nil {
                        Button(selectedID == resource.id ? "✓ 已选择" : "选择此资源") { selectedID = resource.id }
                            .buttonStyle(DemoSecondaryButtonStyle())
                    } else { Text("不可新选；请选择其他资源或移除。") }
                }
            }
            Button("确定选择") { onConfirm(selectedID); dismiss() }
                .buttonStyle(DemoPrimaryButtonStyle()).disabled(!selectionValid)
            Button("取消") { dismiss() }.buttonStyle(DemoSecondaryButtonStyle())
        }
        .navigationTitle("选择店铺资源").navigationBarTitleDisplayMode(.inline)
    }
}
