import SwiftUI

struct DemoPage<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoTheme.Spacing.section) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DemoTheme.Spacing.page)
        }
        .background(DemoTheme.ColorToken.pageBackground)
        .foregroundStyle(DemoTheme.ColorToken.primaryText)
    }
}

struct DemoIntro: View {
    let description: String
    var body: some View {
        VStack(alignment: .leading, spacing: DemoTheme.Spacing.small) {
            Text(description).font(DemoTheme.Typography.body)
            Text("本地示例 · 无真实 AI 或发送")
                .font(DemoTheme.Typography.caption)
                .foregroundStyle(DemoTheme.ColorToken.secondaryText)
        }
    }
}
