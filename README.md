# 触达 · iOS 演示骨架

> **2026/10/11 A 阶段更新**：人群模块已实现可编辑的本地演示；共享 DemoSession、版本快照与统一重置已接线。B/C/D 页面仍为原只读骨架，以下原始骨架说明作为基线保留。实际交付/逐项结果/限制请看 [A_AUDIENCE_DELIVERY.md](Docs/DeveloperTasks/A_AUDIENCE_DELIVERY.md)。本机 Xcode 27.0 generic Simulator SDK 构建通过，纯逻辑检查通过；没有已安装 iOS 运行时，尚未完成 UI 运行验收。

本项目为「触达智能营销」建立可点击的原生 iPhone 演示骨架，供四位开发者分别补充人群、方案、发送审批、数据模块。当前仅交付四个首页及各模块的详情占位页，不实现产品说明中的 46 个完整页面。

## 工程与运行环境

| 项目 | 配置 |
| --- | --- |
| 工程、Target、共享 Scheme | `TouchMarketingDemo` |
| Bundle Identifier | `com.touchmarketing.demo` |
| 手机显示名称 | 触达 Demo |
| 最低系统 | iOS 17.0 |
| 设备与方向 | iPhone，竖屏 |
| 语言与框架 | Swift、SwiftUI，Swift 5 语言模式 |
| 工程格式 | Xcode 16+ 的文件系统同步目录，新增 Swift 文件自动参与构建 |
| 本机工具链 | Xcode 26.6（17F113），iOS Simulator SDK 26.5 |
| 依赖 | 仅 Apple 系统框架，无第三方包、数据库和网络请求 |

默认命令行开发目录指向 Command Line Tools；验证命令使用临时 `DEVELOPER_DIR` 指向完整 Xcode，不改变系统配置。最低系统仍为 iOS 17，不因构建 SDK 较新而提升。

## 用 Xcode 打开并运行

1. 打开 `demo/TouchMarketingDemo.xcodeproj`，选择 `TouchMarketingDemo` Scheme。
2. 顶部运行目标选择已安装运行时的 iPhone 模拟器，例如 iPhone 17。若无模拟器，先在 Xcode Settings → Components 下载对应 iOS 运行时。
3. 点击运行按钮，或按 ⌘R。模拟器无需开发者账号和签名 Team。
4. App 默认进入人群页；点击卡片或详情按钮进入详情。使用系统返回按钮、左侧返回手势或页面下方的返回按钮回到首页。
5. 切换底部四个 Tab，分别查看方案、发送审批、数据。

真机演示：连接 iPhone，在 Target → Signing & Capabilities 选择自己的 Team；必要时改为个人唯一 Bundle Identifier，开启手机开发者模式，再选择该设备运行。当前未配置开发者 Team，也未验证真机安装。

## 命令行构建

在 `demo` 中执行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project TouchMarketingDemo.xcodeproj \
  -scheme TouchMarketingDemo -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

所有手动保存的构建产物和日志放入 `demo/.build/`，已忽略，不进入源代码。系统运行 Xcode／模拟器自身所需缓存由系统管理。

## 已具备的演示内容

- 四个 Tab，每个独立 `NavigationStack`，首页进入详情并返回。
- 两个人群，五项评分及品类组成；人群首页默认三项评分。
- 两个方案，首页仅编号、目的、适用客户；详情展示少量话术和资源说明。
- 一条待审批双方案任务：人群 01、2,000 人、30%／70%，预计 600／1,400 人。
- 一个独立历史已发送批次及固定数据摘要：2,000 人触达、168 人成交、196 单、¥29,400、8.40%。
- 共享模型、统一只读 Mock 数据、黑白灰样式、卡片、按钮和空状态组件。
- 四模块独立目录，新增模块内文件无需手动修改工程文件。

比例为只读示例。没有真实／模拟发送按钮，没有数据联动、编辑、筛选、历史版本页面、AI 计算、登录权限或持久化。资源仅文字说明，无链接访问。

## 产品与设计依据

- 产品说明：[完整产品说明副本](Docs/PRODUCT_SPEC.md)，原文位于父项目的 `触达智能营销App_产品说明.md`，实施前完整阅读 V1.0（2026/10/11）；仓库包含完整副本，克隆后不依赖父目录。
- Figma：[手机端静态设计](https://www.figma.com/design/SE3ATdWL7cqhUe1UhhhT6c)。
- Figma 连接器在本次实施时返回 Starter 额度上限，未取得设计上下文或截图。当前按产品说明的黑白灰、编号与信息密度要求搭建占位结构，未进行逐像素 Figma 还原或核验。

## 四人开发任务

[开发任务总入口](Docs/DeveloperTasks/README.md)包含分工、共享接线顺序、跨模块演示主路径及四份完整提示词：

| 开发者 | 模块 | 任务 |
| --- | --- | --- |
| A | 人群；兼任共享基础整合 | [A_AUDIENCE.md](Docs/DeveloperTasks/A_AUDIENCE.md) |
| B | 方案、资源、生日/回访规则 | [B_PLAN.md](Docs/DeveloperTasks/B_PLAN.md) |
| C | 审批、模拟执行、失败重试和记录 | [C_APPROVAL.md](Docs/DeveloperTasks/C_APPROVAL.md) |
| D | 筛选、统计、趋势和方案效果比较 | [D_ANALYTICS.md](Docs/DeveloperTasks/D_ANALYTICS.md) |

任务定义下一阶段的可交互Demo，尚未实现；当前代码功能仍以“已具备的演示内容”为准。四人可并行做各自页面，A先合入单一共享会话的最小基础变更再接保存和联动。

## GitHub 与克隆

现有仓库：[iceflying6397/demo](https://github.com/iceflying6397/demo)。仓库根对应本机demo目录，包含App、产品说明副本、全部协作文档和开发任务；排除构建缓存及个人设置。

```sh
git clone https://github.com/iceflying6397/demo.git
cd demo
open TouchMarketingDemo.xcodeproj
```

GitHub现有可见性和main分支保持原配置。骨架搭建阶段按当时要求未创建commit；本次根据用户新的保存与上传要求，将项目及开发文档保存为Git共享基线。后续四人分别建立feature分支。

## 文档导航

- [整体架构](Docs/ARCHITECTURE.md)
- [多人协作](Docs/COLLABORATION.md)
- [四模块职责](Docs/MODULES.md)
- [数据模型与关系](Docs/DATA_MODELS.md)
- [UI 规范](Docs/UI_GUIDELINES.md)
- [演示范围与验收](Docs/DEMO_SCOPE.md)

## 验证结果

已完成 generic iOS Simulator（arm64／x86_64）及 iPhone 17（iOS 26.5）构建，均为 `BUILD SUCCEEDED`；已安装启动，并实际检查四个 Tab、详情入口、系统返回和四模块返回按钮。Xcode 已成功打开工程。

完整结果与限制见 [DEMO_SCOPE.md](Docs/DEMO_SCOPE.md)。实际运行未覆盖 iOS 17 运行时、真机、小屏及大字体。项目仅用于本地演示；骨架阶段未创建 Git commit，本次仓库准备阶段根据用户要求保存并上传共享基线。
