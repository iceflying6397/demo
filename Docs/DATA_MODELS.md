# 数据模型与约定

> B 分支增补（2026/10/11）：方案领域类型、校验和只读样本已写入独立新文件；共享会话与任务生成已在 PR #4 整合。下文为原骨架模型基线，新增字段、所有权和迁移说明见 [B 对接说明](DeveloperTasks/B_PLAN_INTEGRATION.md)。新增 PlanVersionSnapshot 是方案内容快照，不另建通用 VersionRecord；PlanMetadata 暂按 plan ID 保存资源引用及时间，不改变既有 MarketingPlan 初始化参数。

模型位于 `TouchMarketingDemo/Shared/Models`，统一 fixture 位于 `Shared/MockData/MockDataStore.swift`。类型为轻量值对象，不对应网络响应或数据库表。稳定字符串 ID 用于关联，编号单独存储，不能由数组下标生成。

## 已写入 Swift 的对象

| 类型 | 主要字段及说明 |
| --- | --- |
| `Audience` | `id`、`number`、`memberCount`、`source`、`version`、`scores`、`categoryPreferences`；`displayName` 如人群 01 |
| `AudienceScore` | `dimension`、`value: Int?`；五维枚举，1...5，nil 为依据不足；`displayValue` |
| `CategoryPreference` | `id`、`name`、`percentage`（0...100）；当前按购买件数展示固定示例 |
| `MarketingPlan` | `id`、`number`、`purpose`、`customerStage`、`version`、`message`、`resourceSummary`、`source`、`audienceIDs`；`displayName` 如方案 01 |
| `ApprovalTask` | 稳定 `id`／`number`；可变的人群、版本、`expectedReach`、`reachState`、`allocation`、审批和执行状态；来源、推荐比例、规则 ID 和周期键在创建后不变 |
| `ABAllocation` | `groups` 包含一或两个 `Group`；每组 `planID`、`planVersion`、`percentage`；组 ID 是方案 ID |
| `AnalyticsSummary` | `id`、`startDate`、`endDate`、`audienceID`、`deliveryTaskID`、`performances`、`totals` |
| `PlanPerformance` | `planID`、`planVersion`、`metrics`；当前每个摘要同一方案只一条，不支持重复版本混合条目 |
| `MarketingMetrics` | `reachedCustomers`、`convertedCustomers`、`orderCount`、`revenueInCents`；`conversionRate: Double?` 为计算属性 |

金额使用人民币分的整数，界面转人民币元；百分比分配和品类使用 0...100 整数；转化率使用 0...1 比值，由格式化层显示百分数。计数不得为负；画像 1...5 与品类占比由 fixture 作者遵守，本轮不为所有模型增加表单校验层。

## 已实现的枚举

| 枚举 | 值 |
| --- | --- |
| `CreationSource` | `ai`（AI 创建）、`manual`（手动创建） |
| `AudienceScore.Dimension` | `spending` 消费水平、`frequency` 购买频次、`priceSensitivity` 价格敏感度、`newProducts` 新品偏好、`classics` 经典款偏好 |
| `PlanPurpose` | `nurture` 新客培育、`firstPurchase` 首购转化、`repurchase` 复购促进、`valueGrowth` 价值提升、`relationship` 关系维护、`winBack` 流失召回 |
| `CustomerStage` | `newContact`、`beforeFirstPurchase`、`purchased`、`repeatBuyer`、`lowActivity`、`longInactive`、`any` |
| `ApprovalStatus` | `pending` 待审批、`deferred` 稍后处理、`confirmed` 已确认、`rejected` 已拒绝 |
| `DeliveryStatus` | `waiting` 等待发送、`sending` 发送中、`succeeded` 发送成功、`partiallyFailed` 部分失败、`failed` 发送失败 |

未审批的任务执行状态为 nil。“已发送”是业务列表分组，后续可包含已确认但等待发送的任务，不等于执行成功。

## 关系与稳定 ID

- 人群：`audience-01`、`audience-02`；方案：`plan-01`、`plan-02`。
- `MarketingPlan.audienceIDs` 是人群—方案多对多关系的唯一来源。方案 01 关联两个人群，方案 02 关联人群 01；通过 `store.plans(for:)` 得到反向关系，禁止再维护 Audience.planIDs 导致不一致。
- 待审批 `task-01`（任务 01）引用人群 01 V1 和方案 01／02 V1。
- 历史 `task-history-01`（任务 02）已确认、发送成功，供 `analytics-week-01` 统计引用。历史与待审批使用相同配置作为示例，统计不是待审批任务的未来结果。
- 任务版本引用可追溯；当前 store 只有 V1 对象，没有完整冻结内容。真实的历史详情和任务快照需后续补充，不能直接用最新内容代替旧版本。
- `MockDataStore.audience(id:)`／`plan(id:)` 可返回 nil；页面展示不可用说明。维护 fixture 时须确保所有引用有效。

## A/B 规则

`ABAllocation.init?(groups:)` 校验：一到两个组、方案 ID 不为空且不同、版本为正、比例为正整数、总和 100%。因此单方案只能 100%，双方案各为 1...99%；0% 不构成双组测试。添加第三套方案或重复方案返回 nil。

`expectedCounts(total:)` 单方案返回全量；双方案 A 向下取整，B 取余，人数合计等于任务人数。当前示例 2,000 → 600／1,400。它只是 Demo 的预计人数约定；小样本空组、真实客户去重和分配不在本阶段实现。表单将来应处理 nil 并展示提示，不将固定 fixture 的断言当作用户输入校验。

## 数据口径

固定区间为上海时区 2026/10/05 00:00 至 2026/10/11 23:59:59，时间戳写入 fixture，不依赖设备当天日期。没有时间范围枚举或日期筛选行为。

| 指标 | 方案 01 | 方案 02 | 合计 |
| --- | ---: | ---: | ---: |
| 触达人数 | 600 | 1,400 | 2,000 |
| 成交人数 | 36 | 132 | 168 |
| 订单数 | 42 | 154 | 196 |
| 金额（元） | 6,300 | 23,100 | 29,400 |
| 转化率 | 6.00% | 9.43% | 8.40% |

转化率 = 成交人数 ÷ 触达人数，分母 0 时返回 nil，显示“—”。合计存储在 `totals`，不可对两个百分率取平均。当前互斥同组示例可相加，未来跨任务合计需要去重；本 App 不持有客户名单，不能声称已经执行去重。

## 审批扩展（开发者 C 已写入 Swift）

共享会话是 `DemoSession`，由 App 根创建一次。四模块读写同一会话；B 的 PlanSessionAccess 与 D 的 AnalyticsIntegration 在根接入，C 的 tasks 是 A 的 approvalTasks 别名。`MockDataStore.demo` 仍是重置时的种子。

| 类型 | 说明 |
| --- | --- |
| `ApprovalTaskOrigin` | `aiRecommendation`、`birthdayRule`、`revisitRule`、`manualTest` |
| `TaskReachState` | `known`、`pendingReview`（待核对）、`zeroCoverage`、`unavailable`。待核对不是 0 |
| `DeliverySnapshot` | 确认时冻结的人群、评分、方案正文、资源摘要、比例和分配人数 |
| `DeliveryBatch` | 一次执行。重试更新同一批次的成功／失败人数，不新建批次 |
| `ApprovalRecord` | 稳定 ID、序号、任务、操作类型、实际时间、前后摘要、说明、演示运营人员 |
| `RulePendingTaskRequest` | B 传入规则 ID、周期键、来源、人群版本、预计人数和分配。同一规则＋周期不重复 |
| `DeliveryTouchSummary` | 给 D 的只读触达投影：批次、任务、业务日、版本、分配和成功人数、统计状态。不含成交 |
| `StatisticsReadiness` | 新批次为 `collecting`（统计中）；匹配统计加载后为 `simulated`。只有历史 `batch-history-01` 是 `historicalSample` |


人数规则仍用 `ABAllocation.expectedCounts`。部分失败的演示样本把失败人数定为分配人数的 1/4，因此 600／1,400 得到失败 150／350。重试全部成功后唯一成功触达仍是原分配人数。业务日固定为上海时区 2026/10/11；操作记录另记实际时间。

审批选择器里还有三个人群演示样本，只放在会话中，不改人群页的两张卡片：`audience-03` 零覆盖，`audience-04` 依据不足但本次 400 人，`audience-05` 小样本 50 人。`audience-01` 本次范围是 2,000，不是覆盖数 8,420；`audience-02` 本次范围是 900。


后续规则：发送快照需冻结人群／方案版本和分配；数据需补 `audienceVersion`、批次及归因范围；统计中的未知值须显式表示，不作为 0。多个方案版本合并统计时，应调整 PlanPerformance 的唯一 ID 与分组约定。扩展共享模型必须同时更新本文件、fixture 和相关页面。

## A 阶段已实现的增补（覆盖上文“尚未实现”的人群相关项）

| 类型 | 实际职责 |
| --- | --- |
| `DemoSession` | 单一 Observable 会话、受校验的保存／版本查询／建议处理／统一重置 |
| `AudienceField` | 稳定ID、名称、分类/数值/日期/布尔、说明、属性、识别依据、启用、版本、内置标记 |
| `AudienceRuleCondition` | 稳定条件ID、冻结的字段定义、类型适配操作符、类型化值 |
| `AudienceRules` | 一层 AND/OR、条件数组、识别说明；重复字段拒绝，范围用 between |
| `AudienceSnapshot` | 原 Audience、规则、识别状态、观察期/量表/品类口径/更新时间 |
| `VersionRecord` / `VersionContent` | 共用对象种类/ID/版本/时间/来源/变化摘要，内容分别为人群快照或方案值对象 |
| `DemoSuggestion` | 目标种类/ID/基础版本、变化、依据、影响、可选建议规则、状态/生成版本/处理时间 |
| `DemoClock` | 上海固定演示日；操作留痕用实际时间 |

原 Audience/MarketingPlan/ApprovalTask 的结构及稳定 ID 不改。人群不保存反向方案关系。`AudienceFixtures.swift` 与原 MockDataStore 同在 Shared，包含统一字段、初始规则、建议和联合覆盖样本；Feature 没有业务 fixture。

新增样本：两人群覆盖 8,420／3,160，重叠580，联合11,000。仅完整匹配初始两对象内容时使用联合值；新建／规则修改后的多个范围无预去重摘要则“待统计”，不按人数相加。单个人群在识别完成／0覆盖状态可显示已知覆盖；依据不足和识别中覆盖未知。初始规则为距上次购买不大于90／30天，均新增本地演示约定，非真实后台条件。

保存新规则：新版本识别中，画像 nil、覆盖未知；选择完成场景固定借用人群01的8,420及五维/品类，说明与输入规则无计算关系；依据不足场景全部nil且覆盖未知；空范围场景覆盖0且无画像。识别完成只补充当前同版本结果并记录画像更新时间，不增加版本；完成后锁定，后续版本不影响旧快照。

初始人群/方案 V1 均有类型化记录。旧字段定义随规则冻结；字典修改、停用不回写。人群建议含可采纳 V1 和过期 V0 两条，采纳只保存规则进入识别，不能自动改审批任务版本或历史数据。资源、触达规则、执行批次、趋势及统计状态仍待 B/C/D 开发，本次未将未知成交伪装成0。


## 四模块合并接线（2026/10/11）

A/C 同名会话已合并，保留人群规则、字段及类型化 VersionRecord；审批按版本读取，不另建版本库。C 确认与执行状态保留原批次，累计唯一成功人数接入 AnalyticsBatchStatistics，历史批次单独保留且不重复加入新统计。B 保存与建议生成方案版本和资源快照，规则生成调用 C 同周期去重入口。重置一次恢复四模块、批次、规则生成记录、模拟统计及根导航。审批选择器的边界人群来自只读样本目录，未增加 A 的初始两个人群；移除旧快照演示只阻止审批读取，不删除 A 历史。
