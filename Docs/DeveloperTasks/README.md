# 四人并行开发任务总入口

> 已合入 A 的共享 DemoSession、人群版本与统一重置，以及 D 的筛选、趋势、去重和统计契约，详见 [A 交付记录](A_AUDIENCE_DELIVERY.md)、[D 交付记录](D_ANALYTICS_DELIVERY.md) 与 [会话接口](../COLLABORATION.md)。

> B 的方案页面、草稿与领域逻辑见 [B 交付记录](B_PLAN_DELIVERY.md)，共享接口见 [B 对接说明](B_PLAN_INTEGRATION.md)。保存、规则生成与审批批次统计已接入同一会话，最新证据见 [PR 整合记录](PR_INTEGRATION_20261011.md)；原任务规划保留为开发基线。

本目录包含四份可以直接交给对应开发者或编码助手的完整任务提示词。每份都包括当前基线、负责目录、页面范围、每个动作的本地状态变化、共享约定、边界样本、实施顺序和逐条验收表；直接将整份文件交给开发者，不只截取首页功能列表。

下文保留初始开发计划；实际已实现范围以各模块交付记录和当前代码为准，不能把计划或初始只读骨架说明当作最新功能清单。

## 分工与任务文件

| 开发者 | 主目录 | 完整任务文档 | 必须完成的业务 |
| --- | --- | --- | --- |
| A | TouchMarketingDemo/Features/Audience | [A_AUDIENCE.md](A_AUDIENCE.md) | 来源筛选、六项画像、规则创建编辑、字段字典、模拟识别、历史、建议采纳；兼任共享基础整合 |
| B | TouchMarketingDemo/Features/Plan | [B_PLAN.md](B_PLAN.md) | 搜索筛选、详情、创建编辑、既有资源选择、历史、方案建议、生日和回访规则及待审批生成 |
| C | TouchMarketingDemo/Features/Approval | [C_APPROVAL.md](C_APPROVAL.md) | 任务选择调整、单/双方案比例、稍后/拒绝、人工确认、版本/资源核对、五发送状态、快照、结果、失败重试和记录 |
| D | TouchMarketingDemo/Features/Analytics | [D_ANALYTICS.md](D_ANALYTICS.md) | 三时间范围、编号筛选、摘要与派生指标、双方案趋势、同组/跨任务对比、统计中/零/空状态、批次与版本关联 |

## 仓库及阅读依据

- GitHub：[iceflying6397/demo](https://github.com/iceflying6397/demo)，使用现有main；不另建仓库、不改变可见性。
- 克隆后的仓库根就是原项目demo目录，Xcode工程直接位于根目录；不要再创建嵌套demo。
- [完整产品说明副本](../PRODUCT_SPEC.md)：原V1.0完整复制，保留原文的静态设计阶段描述。本副本不是本次App实现进度报告。
- [当前能力与范围](../DEMO_SCOPE.md)、[模型基线](../DATA_MODELS.md)、[协作约定](../COLLABORATION.md)、[UI规范](../UI_GUIDELINES.md)。
- [Figma参考](https://www.figma.com/design/SE3ATdWL7cqhUe1UhhhT6c)；当前连接器曾额度不足，不能声称已经逐像素验证。

产品说明中的已确认需求优先；任务中注明的Demo约定用于弥补尚待细化的后台口径。后续如调整约定，先由A统一共享契约并更新四份文档，再实施。开发者不能把正式生产功能全部搬进Demo。

## 如何立即开始并行开发

1. 四人克隆同一main基线，分别建立feature/audience、feature/plan、feature/approval、feature/analytics。
2. 四人各自阅读需求与任务，并提最小共享字段清单。A优先完成统一会话、根注入、版本基础和重置接线；B/C/D可并行做读视图、筛选和表单草稿。
3. A的小基础变更先合入main，其他分支同步。共享模型增补按领域分文件，小变更整合；四人不能同改MockDataStore或根App。
4. 接入本地保存、历史和状态。表单草稿局部，提交的实体共享，不建四个全局store。
5. B规则生成接C的pending任务入口；C执行结果接D的统计状态。先实现各自流程，再合并跨模块闭环。
6. A集中验证四Tab和共享版本关系，四人各自提交模块验收记录。后续PR须经团队review，不自动覆盖或合并别人开发中的工作。

## 必须达成的联合演示

人群查看/编辑 → 方案查看/编辑 → 审批修改50/50或恢复30/70 → 人工确认模拟发送 → 结果/失败重试 → 数据查看同一批次与历史对比 → 采纳建议生成新版本 → 再查看旧发送快照仍保持旧内容。

联合验收必须证明：保存确实改变本地会话，取消确实不变，旧版本确实可追溯；发送仅本地模拟，成交未知时显示统计中，不伪造真实营销结果；四模块切换不重置会话，统一重置同时恢复四模块。

## 模块进度如何记录

每人完成后新增自己的A_AUDIENCE_DELIVERY.md、B_PLAN_DELIVERY.md、C_APPROVAL_DELIVERY.md或D_ANALYTICS_DELIVERY.md，逐条填写本任务验收编号、构建目标、演示路径、共享改动和限制。当前仓库不创建空交付文档，不预填完成勾选。

验收表的所有功能都属于下一阶段必交付，实施顺序不代表后半段可以省略。对产品尚未确认的恢复历史、真实接口、正式评分/归因/去重算法保持范围外。
