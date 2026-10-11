# UI 规范

## 视觉与设备

黑、白、灰；页面白色，主要文字及关键操作黑色，说明灰色，卡片浅灰。不用颜色区分状态或方案。根视图固定浅色；系统状态栏、返回导航和底部 Tab 使用原生控件。设备限定 iPhone 竖屏，Figma 的 390×844 是参考尺寸，不能把页面固定成像素画板。

本轮未获得 Figma 设计上下文（连接器额度上限），以产品说明为占位页依据。后续实现具体页面前按对应 Figma 节点核对，但公共 token 的变更应集中维护，不能每位开发者另建不同主题。系统导航和 Tab 外观随 iOS 版本变化，本轮不强制替换系统外观。

## DemoTheme

| Token | 当前值与用法 |
| --- | --- |
| `ColorToken.black`／`white` | 黑、白；按钮前景／背景 |
| `gray`／`secondaryText` | 灰度 0.42，辅助说明 |
| `pageBackground` | 系统背景（浅色为白） |
| `cardBackground` | 灰度 0.96 |
| `primaryText` | 黑色 |
| `border` | 灰度 0.85 |
| `Spacing.small/medium/large/page/section` | 8／12／16／20／24 pt |
| `Radius.button/card` | 12／16 pt |
| `Typography.title` | title2 semibold，区块总览 |
| `heading/body/caption` | headline／body／footnote |

字体使用系统语义样式支持 Dynamic Type。正文可多行，页面使用 ScrollView，值行使用 ViewThatFits 在大字体或窄屏改为纵向。按钮至少 44 pt 高，不硬编码屏幕宽高。标题用系统 navigationTitle，详情 inline。无需自定义动画或装饰阴影。

## 公共组件

- `DemoPage { ... }`：白底纵向滚动页面、20 pt 页面边距、24 pt 区块间距。
- `DemoIntro(description:)`：简短模块说明及本地演示标识。
- `DemoCard { ... }`：浅灰圆角容器，16 pt 内边距；接受任意 View，不包含业务逻辑。
- `DemoValueRow(title:value:)`：统一标签与值，适配窄屏及较大字体，辅助功能合并读出。
- `DemoPrimaryButtonStyle()`：黑底白字，应用于真正的主操作或 NavigationLink。
- `DemoSecondaryButtonStyle()`：白底灰边黑字，当前用于详情的返回按钮。
- `DemoEmptyState(title:message:)`：通用缺省／占位信息，本阶段用于说明详情后续范围，不制造不可点击的伪按钮。

示例：

```swift
DemoCard {
    Text(plan.displayName).font(DemoTheme.Typography.heading)
    DemoValueRow(title: "目的", value: plan.purpose.rawValue)
}
NavigationLink("查看详情") { PlanDetailView(plan: plan, store: store) }
    .buttonStyle(DemoPrimaryButtonStyle())
```

任何暂未实现的入口用文字说明，不添加空动作 Button。不使用图片拼接整页，不加载远端图片。当前图标为系统 SF Symbols，AccentColor 为黑色。

## 编号与各模块展示

`DemoFormat.numbered` 保证最少两位编号：人群 01、方案 01、任务 01，超过 99 自然扩展。内部 ID 永不直接作为业务名称，不根据排序重编号。版本显示 V1 等。

- 人群：首页编号、覆盖人数、消费水平／购买频次／价格敏感度；详情五项评分＋主要品类组成六项画像，分值明确显示“4 / 5”。分数高不代表客户更优。
- 方案：首页每条只展示编号、目的、适用客户；详情再展示话术、资源、版本与关联人群。
- 审批：明确待审批状态、人群编号、本次预计人数、方案编号、比例及预计组人数；详情声明最多两方案和每客户一组，当前不展示假发送控件。
- 数据：明确日期范围、人群／方案编号和指标单位，转化率两位小数；数据来自历史固定样本。未来趋势用实线／虚线和编号图例区分，不能只靠颜色。

日期使用上海时区及中文区域；金额从分转为人民币显示；计数采用千位分隔；未知转换率为“—”。格式化统一使用 `DemoFormat`，不在各模块复制格式器。

## A 人群阶段实际 UI

保留 DemoTheme 全部 token，未增加另一套主题。人群首页卡片默认核心三评分，展开独立按钮不触发导航；详情五格灰度条同时提供数值／分档及解释，缺失显示待识别／依据不足。字段/规则使用原生 Form、Picker、DatePicker、Toggle；草稿修改时阻止滑动关闭，取消先提示放弃或保留。

大字体来源筛选切换为菜单；普通字号用三段选择。页面不固定宽高，评分条自适应宽度；值行沿用 ViewThatFits，所有内容可滚动，按钮至少44pt。窄屏和大字体实际运行验收待安装模拟器运行时，不能仅凭代码结构视为通过。

Figma MCP 在2026/10/11返回无编辑访问权限；随后通过 Chrome 已打开3:66总览节点，查看到390×844、白色背景、#E0E0E0边框及卡片/筛选/底部导航结构。Chrome 自动化后续被工具的当前URL访问限制终止，没有完成全部人群二级页面或逐像素对照；按最新产品说明和现有原生组件实施。
