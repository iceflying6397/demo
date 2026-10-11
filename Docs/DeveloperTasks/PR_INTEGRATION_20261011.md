# PR #3 / #4 冲突处理与四模块联调

日期：2026/10/11，Asia/Shanghai。整合在原 demo 目录完成，没有克隆、项目副本、嵌套工程或第二个全局会话。

## 冲突处理

- PR #3：Docs/DeveloperTasks/README.md 的同位置进展说明冲突。保留 A/B/D 进展并明确初始骨架是历史基线。方案模块与 main 合并构建、方案领域检查通过后合入。
- PR #4：Docs/DATA_MODELS.md、AppRootView.swift、DemoSession.swift 冲突。保留 A 唯一 DemoSession、人群规则／字段／识别／版本／建议及根重置，把 C 的审批任务、快照、批次、操作记录和执行方法合入同一类。tasks 是 approvalTasks 的别名，没有另一份任务数组或版本目录。
- C 当前人群查询改用 approvalAudience，发送版本仍经 A 的类型化历史读取。C 边界人群只在只读审批目录中展示，A 初始仍是两个人群。缺失旧快照演示仅阻止 C 读取，不删除 A 的历史记录。
- 实现 B PlanSessionAccess，由唯一会话保存方案、元信息、资源快照、建议、规则和周期记录。生成任务实际调用 C；规则 24 人范围不会因只调整方案／比例而扩大成 2,000。
- 根注入 B 的 planSession、D 的 analyticsIntegration，以及同一 Observable 会话；根 resetGeneration 恢复四个 NavigationStack。
- C 确认／执行结果将累计唯一成功人数写入 D 的 reducer；历史批次不重复纳入新批次。配置或人数无变化不发布重复更新。成交未回流保持 nil／统计中；只有完全匹配的 50/50 样本可载入，重复加载不累加。载入后 C/D 统计状态一致。
- 资源检查按实际发送的方案版本读取资源引用，不能用最新版资源冒充旧版本。

## 可复现验证

Xcode 26.6，iOS Simulator SDK 26.5，最低部署 iOS17。构建：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project TouchMarketingDemo.xcodeproj \
  -scheme TouchMarketingDemo -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

最终结果 BUILD SUCCEEDED；仅未使用 AppIntents 的元数据跳过提示。

```sh
sh Docs/DeveloperTasks/Validation/run-session-checks.sh
sh Docs/DeveloperTasks/Validation/run-plan-checks.sh
sh Docs/DeveloperTasks/AnalyticsValidation/run.sh
```

- PASS: 56 audience/session checks。
- PASS: 62 integrated A/B/C/D session checks。
- 方案领域检查 PASS：保存／资源／版本／建议／日期规则／旧预览／周期去重。
- 61 meaningful analytics checks passed。
- 共 179 项计数检查及方案领域 smoke；并非 179 个 UI 验收场景。
- 原 A 检查的重置预期改为恢复集成后的初始任务（包括 C 增补的来源与推荐信息）；覆盖范围未缩小。脚本补上 C 模型依赖，无新增 Xcode 测试 Target 或第三方依赖。

本地日志：.build/pr4-integration-build.log、pr4-session-checks.log、pr4-plan-checks.log、pr4-analytics-checks.log，均未提交。

## 实际模拟器验证与演示步骤

在现有 375pt iPhone SE（Analytics Narrow Validation，iOS26.5）安装并启动集成工程：

1. 人群首页保留 2 个人群／去重覆盖11,000。切审批，任务01为2,000人、30%／70%。
2. 输入50%为草稿，保存后确认页显示两组各1,000；人工确认，生成唯一 batch-task-01。
3. 预设部分失败并推进开始／结束：成功750／750，失败250／250。数据Tab出现此批次，唯一触达1,500，成交／订单／金额／转化率统计中。此时载入无匹配，结果仍未知。
4. 返回原审批结果，重试失败部分并推进结束：成功1,000／1,000，重试次数1、总成功2,000。数据同步为2,000，不累加成3,500。
5. 数据页载入匹配模拟统计：成交130、订单150、金额¥22,500、转化率6.50%。再载入显示重复操作未新增结果，数值不变。
6. 方案01编辑移除资源并保存，生成V2；切审批，原批次仍显示方案01 V1及发送时资源／话术。
7. 切人群，演示工具→重置演示→重置所有模块。回数据为历史168成交／8.40%，无新批次；根导航与页面草稿恢复。

最终版本实际验证生日规则生成任务03、24人、待审批，预览显示同周期已生成；任务编辑器与服务端分组校验使用同一个24人范围。其余规则同周期防重复、A 编辑对 C 版本差异、B 保存／建议、旧资源、C 发送及重复确认／重试、D 匹配载入与历史保护、四模块重置在集成检查中覆盖。未逐一重新执行 A/B/C 的全部 UI 验收表；iOS17运行时、真机、返回手势和 Figma 像素还原未验证。本次原生运行验证重点是合并影响和跨模块路径，不将原 PR 的未验证项全部改为通过。

## 保留范围

仍是确定的本地 Demo：规则不会真实筛选客户，不执行真实 AI／发送／网络／归因；新的人群规则没有预置触达范围时 C 显示待核对。新发送配置无匹配统计时继续统计中。工作区原有 project.pbxproj 格式化改动保留且未提交；构建缓存、签名和个人配置不进入 PR。
