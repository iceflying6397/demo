# B → A/C 对接说明

2026/10/11，分支 `feature/plan`。用户已确认 A/C 基础尚未完成，本次先完成 B 模块及对接交付。

## 本次边界

修改仅涉及 `Features/Plan`；共享增补为三个独立新文件，供 A 单独 review 合入：

- `Shared/Models/PlanDomain.swift`：资源、规则、内容与快照、建议、共享会话消费接口。
- `Shared/Models/PlanValidation.swift`：无状态校验与构建函数。
- `Shared/MockData/MockDataStore+Plan.swift`：统一种子的只读扩展。

没有改动 App、工程配置、既有 Shared 文件及其他 Feature。没有创建 `DemoSession` 或另一个可变全局 store。新增文件通过现有 Xcode 同步目录参与构建。

当前 B 页面的 `init(store:)` 保留。未注入共享会话时，全部业务展示来自 MockDataStore，只有筛选、表单、资源选择、预览等局部状态；界面明确不提供伪保存、伪采纳或伪生成成功。A 完成接线后启用提交操作。

## A：唯一会话持有与注入

让唯一 `@MainActor @Observable DemoSession` 遵循 `PlanSessionAccess`。该协议不是新 Repository；仅在共享会话尚未合入时隔离编译依赖，可以在最终集成时直接改为具体 DemoSession 环境类型。

会话已有 `plans`、`audiences`，不要为 B 再复制一份。新增以下存储字段，从同一个 seed 初始化一次：

| 字段 | 初始化 |
| --- | --- |
| planMetadata | seed.planMetadata |
| planVersions | seed.planVersions |
| storeResources | seed.storeResources |
| planTemplates | seed.planTemplates |
| planSuggestions | seed.planSuggestions |
| touchRules | seed.touchRules |
| ruleGenerations | 空数组，由 C 成功生成时写入 |
| planRuleRanges | seed.planRuleRanges |
| planReferenceDate | MockDataStore.planReferenceDate |
| planRecommendedPrimaryPercentage | MockDataStore.planRecommendedPrimaryPercentage（30，双方案样本） |
| ruleGenerationAvailable | C 的真实 pending 入口接通后才返回 true |

`MarketingPlan` 暂不增改初始化参数，资源 ID 与时间用 `planMetadata[plan.id]` 显式关联；`resourceSummary` 仅作兼容文字，提交时从资源推导。若 A 选择将这些字段内联到 MarketingPlan，应一次迁移 seed、版本和 C 消费处，不创建第二套关联真相。

根只创建一次 DemoSession，方案入口仍为 `PlanHomeView(store: seed)`，在根或方案导航栈注入：

```swift
.environment(\.planSession, session)
```

协议 getter 必须直接读取同一 Observable 会话的属性，不能返回初始化时捕获的缓存。SwiftUI body 经 PlanContext 读取它们时应跟踪同一实例。集成验收必须检查保存后详情即时刷新及跨 Tab 一致性。

统一重置时恢复所有 seed 字段、清除下面的提交幂等记录，并由 A 的根重置代次重建导航与局部草稿。B 没有自己的重置按钮。

## A：写入事务

所有协议方法同步运行在 MainActor；校验完一次性提交，无 await 中断，不在事务之前改变现有数组。

### savePlan

1. 按新建 request.id 查会话的新建提交记录。重复提交相同请求返回原保存结果；同 ID 不同请求报错。编辑请求按 ID / baseVersion 校验，不允许过期草稿覆盖。
2. 调用 `PlanValidation.revision(...)`，传入当前 plans、metadata、资源、人群、固定参考日、下一个稳定编号及 `Date()` 实际记录时间。
3. 返回 nil 表示内容标准化后无变化，返回当前对象，不能追加版本。
4. 有结果时替换或追加 `revision.plan`，设置 metadata，追加 snapshot，原子完成。保留已有历史快照；新建编号由会话单调分配。
5. 返回保存对象。不要修改 approvalTasks 的引用版本，历史统计也不变化。

可直接采用的核心提交片段（放在会话方法中）：

```swift
let revision = try PlanValidation.revision(
    request: request, plans: plans, metadata: planMetadata,
    resources: storeResources, audiences: audiences,
    referenceDate: planReferenceDate, nextNumber: nextPlanNumber, now: Date())
guard let revision else {
    guard let current = plans.first(where: { $0.id == request.id }) else {
        throw PlanValidationError("方案不存在。")
    }
    return current
}
if let index = plans.firstIndex(where: { $0.id == revision.plan.id }) {
    plans[index] = revision.plan
} else {
    plans.append(revision.plan)
    nextPlanNumber += 1
}
planMetadata[revision.plan.id] = revision.metadata
planVersions.append(revision.snapshot)
return revision.plan
```

新建请求 ID 在草稿初始化时生成一次，页面提交成功后替换为结果视图，不能再次点击保存。数据层仍需做上述重复请求检查。纯函数遇到重复新建 ID 会阻止追加，即使尚未实现“返回原结果”也不会重复创建。

### adoptPlanSuggestion / deferPlanSuggestion

按 ID 读取当前建议，不接受页面传来的可变建议副本。采纳调用 `PlanValidation.adoption(...)`；同时更新方案、元信息、快照，以及建议的 status = adopted、handledAt、resultingVersion。任一校验失败必须全不提交。

暂不采纳只更新建议 status = deferred 和 handledAt，不修改方案；已采纳不能退回 deferred。deferred 可再次确认采纳，仍校验基础版本。采纳重复请求报可读错误，不追加版本。

### saveTouchRule / setTouchRuleEnabled

调用 `PlanValidation.rule(...)` 进行 ID、revision、时间、单／双方案约束校验；相同配置返回旧规则，不增长 revision。新规则编号由会话分配。开关操作先按 ID 找当前配置，只改 isEnabled，再走同一方法，不能写页面捕获的过期配置。

保存规则不调用任务生成。规则选择当前方案 ID，预览时解析最新方案版本；已生成记录保存值快照，后续修改不会回写。

## C：生成待审批入口

B 只传 `PlanRulePreview`。`generatePendingTask(from:)` 的实现与审批任务创建属于 C，下面是必须满足的原子流程：

1. 重新按 preview.rule.id 读取当前规则；不存在报错。
2. 用 `PlanValidation.preview` 和会话当前方案、metadata、资源、人群、固定范围重新计算 current。
3. 调用 `PlanValidation.validateGeneration(preview:current:generations:)`：旧预览、不存在／过期资源、禁用、零匹配、分组为空、本周期重复均阻止。
4. 通过 C 唯一构造入口追加 `approvalStatus = .pending`、`deliveryStatus = nil` 的任务；其 allocation、audienceVersion、expectedReach 来自通过校验的 current。
5. 冻结 current 中的规则配置、来源、方案内容／版本、资源、人群及范围说明，作为 C 的来源／快照结构，不能只保存最新对象的引用。
6. 同事务追加 `PlanRuleGeneration(taskID:taskNumber:createdAt:preview:)`，返回该记录。若任务创建失败，不记录周期已生成。
7. 审批 Tab 必须从同一会话显示新增任务。只有该接线完成时 ruleGenerationAvailable 才为 true。

去重键 = 规则稳定 ID + 上海参考日期。Demo 显式模拟“一天内此规则的到期卡片”，回访三／六个月决定样本匹配条件，不能通过修改规则 revision、生成时刻、方案或回访周期绕过当天去重。正式周期／优先级口径仍由产品确认。

资源有效性共用 `StoreResource.invalidReason(on: planReferenceDate)`；执行前 C 仍需校验，不能凭历史曾有效绕过现时不可用。历史显示使用快照 `resourceCheckedAt`，与实际操作记录时间分开。

## 最小集成回归

1. 新建纯话术方案，切换 Tab 后仍存在，C 方案选择器能读取。
2. 编辑方案 01 得到 V2，原 V1 资源、话术及 task-history-01 保持不变。
3. 两个页面基于同一版本编辑，先保存后另一页被版本冲突阻止；同内容不增版本。
4. 建议确认生成一次版本；旧基础建议被阻止；暂不采纳只改建议状态。
5. 生日规则预览 24 人、三个月回访 120 人、六个月回访 0 人；这些是预去重 fixture，并非真实订单计算。
6. 确认生成后实际出现在 C Tab；重复、改配置后重复、零范围、禁用均无新任务。
7. 预览后更改方案或规则，再确认必须阻止，重新预览后才允许。
8. 旧生成记录展示原配置与版本。统一重置恢复四模块并清除导航、草稿和幂等记录。

这份文档是对接契约，不代表共享会话或 C 生成方法已经实现。最终 B06/B07/B10/B11/B14/B15/B17/B18 必须在集成分支验收。
