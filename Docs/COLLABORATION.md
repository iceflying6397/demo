# 多人协作

## 建议分工

路径均相对 `demo/TouchMarketingDemo`。

| 开发者 | 模块 | 主要目录 | 首个文件 |
| --- | --- | --- | --- |
| A | 人群 | `Features/Audience` | `AudienceHomeView.swift` |
| B | 方案 | `Features/Plan` | `PlanHomeView.swift` |
| C | 发送审批 | `Features/Approval` | `ApprovalHomeView.swift` |
| D | 数据 | `Features/Analytics` | `AnalyticsHomeView.swift` |

模块负责人可在自己的目录增加组件、表单、选择器和局部 Route。命名始终带模块语义，例如 `AudienceEditView`、`PlanResourcePickerView`、`ApprovalAllocationView`、`AnalyticsFilterView`；不使用四份同名 `DetailView.swift`、`ViewModel.swift` 或 `MockData.swift`。

## 公共文件约定

- `App/`、`Shared/`、资源、工程配置由一名轮值整合者维护。四位开发者主要修改各自 Feature，模块已有首页签名保持 `init(store:)`，内部扩展无需修改入口。
- Tab 名称、顺序或根页接口变更先统一，再由整合者一次修改 `AppTab` 和 `AppRootView`。不要各自增加根导航或复制 App 入口。
- 共享对象只能在 `Shared/Models` 定义。先讨论字段、可空性、ID、单位、版本关系，再实现最少必要字段，并同步 `DATA_MODELS.md` 及 Mock 数据。
- 通用组件至少有两个模块真实需求时再提取到 `Shared/Components`；组件只接受展示值或操作闭包，不包含某模块的筛选、审批或发送逻辑。同步 `UI_GUIDELINES.md`。
- 四个模块只能使用统一 `MockDataStore`；增加样本要保留现有稳定 ID，检查引用和数值。禁止复制 fixture 到 Feature。
- 如果新增共享可变状态，由整合者集中改变根注入和容器；不要让四个人分别改静态 store 的类型。
- 新 `.swift` 放到同步的 App 源码目录即可。不手动维护 Sources 列表，不把开发说明／构建产物放到源码同步目录，避免被打包。

## 分支与合并建议

共同基线通过验证后分别建立 `feature/audience`、`feature/plan`、`feature/approval`、`feature/analytics` 分支。公共改动先以小变更合并，其他分支同步基线，再推进模块页面。Feature 变更和公共模型变更尽量拆开，避免公共文件成为大范围合并热点。

合并前更新公共文档和样本；合并后执行一次整体模拟器构建及四 Tab 点击检查。不要提交 `.build`、`xcuserdata`、个人签名 Team 或个人本地设置。骨架搭建阶段未创建 commit；随后用户明确要求保存并上传 GitHub，仓库准备阶段会创建共享基线提交。后续模块开发仍按分支和 PR 协作。

## 模块提交前自查

- [ ] 文件主要位于负责的 Feature；没有依赖其他 Feature 的具体 View。
- [ ] 首页、详情、返回和切换 Tab 可用；未重复创建根导航栈。
- [ ] 新文件在 Xcode 自动出现并参与 Target；工程能构建。
- [ ] 数据来自 Shared，引用 ID 可查到，人群和方案编号稳定。
- [ ] 样式使用 DemoTheme／公共组件；小屏和较大字体可滚动查看。
- [ ] 不加入网络、第三方依赖、数据库或真实发送。
- [ ] 不存在无动作按钮；未完成的能力用说明展示。
- [ ] 公共模型／样式／Mock 修改已协调并同步对应文档。
- [ ] 本次实现范围、模拟状态及限制清楚标记。

用 README 的命令编译；点击验证采用 `DEMO_SCOPE.md` 的路径。当前没有单元测试 Target 或覆盖率门槛。

## 下一阶段具体任务与共享接线

四份详细任务见 [DeveloperTasks/README.md](DeveloperTasks/README.md)。本节定义准备开发的协议，不代表相关代码已经存在。

开发者 A 兼任共享基础和最终集成维护者，只有 A 集中修改 App、公共主题、项目配置与会话接线。领域负责人提出 Shared 类型和样本需求，A 用独立公共变更整合；A 不代替 B/C/D 写业务页面。当前所有首页 init(store:) 仍保持不变。

| 计划能力 | 领域定义负责人 | 整合和文件归属 |
| --- | --- | --- |
| 单一 @Observable DemoSession、根注入、统一重置 | A | Shared/State、App，由A一次接线 |
| 人群规则、字段字典、识别元信息 | A | Shared/Models；A的人群专属表单在Audience |
| 通用版本元信息和类型化快照 | A，B/C提供内容需求 | Shared/Models，不重复定义VersionRecord |
| 既有资源、触达规则和规则配置样本 | B | B提出资源/规则字段，A集中合入Shared |
| 任务来源、推荐值、生成周期去重、确认/执行快照、操作/重试 | C | C提出并实现最小逻辑，A接共享入口；页面在Approval |
| 日期范围、统计状态、趋势、批次查询和预去重摘要 | D | 跨模块类型和fixture进Shared，由A整合；临时筛选在Analytics |
| 目标对象/基础版本/建议状态/变更摘要 | A/B | 共用最小数据约定，建议页面各模块自己实现 |

最少状态流：MockDataStore.demo作为唯一seed → 根DemoSession一次初始化 → 页面从session读取已提交对象，draft/filter用局部State → 保存/确认才替换共享对象 →切Tab继续读取同一实例。一个简单容器足够，不增加网络层、泛型Repository或复杂状态框架。

整合者先提供可构建的小基线，其他开发者在它完成前可做读取页面和草稿，完成后同步分支接写入。不要等待A完成全部人群功能才启动B/C/D，也不要各人复制业务数组成为最终独立真相。

统一重置需恢复所有seed、版本、规则、建议、任务、结果并清空当前导航/草稿/筛选。可用简单重置代次让根重新创建页面局部状态，具体最小实现由A决定；禁止每个模块自己提供互不相干的重置。

固定演示参考日2026/10/11，时区Asia/Shanghai。资源有效性、规则预览和分析范围共用它；记录实际操作时间时与演示统计业务日期区分。期间合计由Shared预去重fixture提供，不能从人数数组盲目相加。

规则生成接口由C定义，B传规则配置/范围，A接入session；保存规则不自动执行。确认生成独立批次/冻结快照，重试只更新该批次失败范围。D读取唯一成功触达并默认显示成交统计中；载入明确匹配的模拟统计才显示已知成交。原task-history-01/analytics-week-01始终独立保留。

只有App维护跨Tab路由；Feature可以通过ID请求跳转或给出明确Tab指引，不能互相实例化具体View。共享操作必须在数据层检查ID/版本/状态，按钮禁用不替代校验；用户输入不得用force unwrap或precondition作为错误处理。

## A 已实现的共享接线（2026/10/11）

`DemoSession` 现已存在，由 `AppRootView` 用 `@State` 创建一次，并通过 `.environment(session)` 注入四个 NavigationStack。A 首页另外接收同一实例；保留 `init(store:)` 的独立 Preview 回退初始化，不要求旧预览提供 environment。B/C/D 首页签名及文件保持原样，根每次从 session 投影只读 store；正式接写入时使用 `@Environment(DemoSession.self)`，不要新建会话。

调用约定：

- `audiences`、`plans`、`approvalTasks`、`analytics`、`fields`、`suggestions`、`versions` 只读查询；写入必须调用方法。
- `saveAudience(id:baseVersion:rules:) throws -> AudienceSnapshot`：新建传 nil/nil；更新必须带基础版本；无变化不生成版本；新建编号在会话内递增。
- `audience(id:)` 读当前；`audienceVersion(id:version:)`、`planVersion(id:version:)` 查类型化旧内容；缺失返回 nil，禁止回退最新。
- `completeRecognition(id:version:scenario:)`：只完成当前识别中版本一次，不增加版本；已完成版本不会再被刷新改写。
- `saveField(_:)`：名称和分类属性校验，字段版本并发校验；冻结旧规则定义。停用字段仅允许原有未变化条件继续保留。
- `adoptSuggestion(id:)`：检查目标、状态和基础版本，原子保存版本及采纳记录；`deferSuggestion(id:)` 只改处理状态。
- `savePlan(_:baseVersion:)`：B 的现有方案更新最小入口，保留编号且传入 Vn+1；新建、资源检查和规则生成待 B/C 领域实现后小变更扩展。
- `updatePendingTask(_:)`：C 的草稿调整入口；禁止修改已确认／历史任务，检查人群及方案旧版本引用；不实现确认／执行。
- `reset()` 恢复整份 seed、版本、字段、建议和所有模块的存储；`resetGeneration` 令根重建导航、筛选和表单。入口位于四模块首页右上角演示工具，先确认。

固定业务参考日为 `DemoClock.referenceDate`（上海 2026/10/11 12:00）；保存及采纳记录用实际操作时间，两者分开。画像元信息只用于解释固定样本，不声称算法已实现。

为兼容 C 当前只读页面，根传 `approvalStore`，其人群画像来自任务所引用版本；根显示最新版变化提醒。此适配针对现有单一人群版本任务样本。C 完成多任务版本选择后，应逐任务使用 `audienceVersion`／`planVersion`，不能用一个扁平 store 表达同对象多个版本。新建人群已在 `session.audiences`／`session.store` 可查；C 选择器尚未开发，故 UI 联合验收仍待 C 接线。

B 的资源／规则、C 的冻结执行批次／操作重试、D 的趋势／联合去重结果仍按各自任务提出最小类型后整合；本次不替领域负责人设计未使用的模型或业务页面。共享基础独立提交在 feature/audience，交团队 review 后优先合入，不自动合并 main 或通知其他聊天。

## PR #3/#4 整合后接口

唯一 DemoSession 为 MainActor Observable。tasks 与 approvalTasks 为同一集合，C 使用 approvalAudience／audienceRevision／planRevision，A 保留 audience 的 AudienceSnapshot 签名。B PlanSessionAccess 写入和 C 规则待审批入口已接通；D analyticsIntegration 由根从会话观察值构造，加载闭包调用 loadAnalyticsStatistics。重置恢复所有模块，历史批次不重复计入新统计。完整说明及可复现检查见 DeveloperTasks/PR_INTEGRATION_20261011.md。
