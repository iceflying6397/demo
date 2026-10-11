# 开发者 A · 人群交付记录

日期：2026/10/11，Asia/Shanghai。分支：feature/audience。基线：bab04b9。

## 实现结果

已实现来源筛选及清除、范围去重覆盖、按稳定ID展开画像、完整详情/评分说明、规则新增编辑、类型适配条件及AND/OR、字段字典新增编辑启停、确定的模拟识别、版本列表/快照、建议依据/差异/确认采纳/暂不采纳/过期阻止及采纳结果。

保存真实改变本地共享会话；无变化不生成版本；取消草稿不写入；新建稳定编号；编辑V1→V2且保留V1；识别完成仅补同版本结果一次。分类/数值/日期/布尔均可用于规则。分类名称/选项重复、数值解析、区间倒置、条件重复、类型不匹配、停用新引用和过期基础版本在数据层校验。

共享基础独立提交，包含 Observable DemoSession、字段/规则/画像元信息、类型化人群与方案版本、建议状态及统一fixture；App根唯一注入、四模块只读投影及确认重置接线在模块提交中完成。B/C/D业务文件未修改。原ID、Tab顺序、iOS17、工程配置及历史统计保留。新资源/触达规则/执行批次/趋势类型仍待对应领域开发提出，未创建未使用的框架。

## 验证环境与结果

- 本机 Xcode 27.0 (27A266a)，SDK iPhoneSimulator 27.0；最低部署iOS17不变。
- 共享基础早期构建：`.build/build-foundation.log`，BUILD SUCCEEDED。
- 完整模块 generic iOS Simulator Debug构建：`.build/build-audience.log`，BUILD SUCCEEDED；最终增量检查记录 `.build/build-final.log`。
- 56项纯逻辑检查：`Tests/AudienceSessionChecks.swift`，PASS。执行日志 `.build/audience-checks.log`；验证规则、字段、版本、识别、采纳和统一重置，无额外测试Target或依赖。
- 本机 `simctl list runtimes` 与 devices均为空：没有已安装iOS运行时，故未启动、安装或点击App，也未完成系统返回/四Tab实际点击/窄屏/大字体截图验收。不能把构建和纯逻辑检查当作UI验收。
- 构建仅有未使用AppIntents的元数据跳过提示，不影响此Demo。

复现构建：

```sh
xcodebuild -project TouchMarketingDemo.xcodeproj \
  -scheme TouchMarketingDemo -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

复现纯逻辑（macOS，须可执行系统 Swift 宏）：

```sh
mkdir -p .build
swiftc -module-cache-path .build/ModuleCache -o .build/audience-checks \
  TouchMarketingDemo/Shared/Models/*.swift \
  TouchMarketingDemo/Shared/MockData/*.swift \
  TouchMarketingDemo/Shared/State/*.swift \
  TouchMarketingDemo/Shared/Utilities/*.swift \
  TouchMarketingDemo/Features/Audience/AudienceRuleDraft.swift \
  Tests/AudienceSessionChecks.swift
.build/audience-checks
```

## 逐项验收

下表“逻辑通过”指可执行检查通过；UI动作均待有运行时后实机/模拟器复验，未伪填完成。

| 编号 | 本次证据与结果 |
| --- | --- |
| A01 | 逻辑通过：两个人群；01覆盖8420，评分4/2/1/5/2；UI初屏待运行 |
| A02 | 逻辑通过：AI/手动各一条；来源Picker/清除接线完成，点击待运行 |
| A03 | 独立展开按钮，Set按ID维护，不包NavigationLink；展开/折叠点击待运行 |
| A04 | 详情/量表页/系统导航已实现并编译；实际返回及六项布局待运行 |
| A05 | 逻辑通过：无条件/重复条件/NaN/类型不符/倒置范围均拒绝，不保存 |
| A06 | 逻辑通过：局部草稿不影响共享实体；修改后取消确认/滑动关闭保护已实现，点击待运行 |
| A07 | 逻辑通过：新编号03/V1，共享store可查；C目前没有选择器，联合UI待C开发 |
| A08 | 逻辑通过：01编辑V2、ID编号不变、V1完整冻结；历史页导航已编译 |
| A09 | 逻辑通过：分类字段保存/去空白/选项去重校验及规则引用；表单选择点击待运行 |
| A10 | 逻辑通过：停用后阻止新引用，旧规则字段定义仍可读；启停入口已实现 |
| A11 | 逻辑通过：不足为nil而非低分，0覆盖单独状态；界面无客户名单 |
| A12 | 逻辑通过：查看/草稿不改变建议或人群；确认取消按钮无写入，点击待运行 |
| A13 | 逻辑通过：采纳生成一个V2、状态/时间/版本记录完整、重复采纳被拒绝 |
| A14 | 逻辑通过：过期/基础版本不一致阻止；界面显示原因且禁用采纳 |
| A15 | 根唯一引用接线完成；纯逻辑store读取保留保存内容；切Tab实际点击待运行 |
| A16 | 逻辑通过：人群/方案/任务/字段恢复seed；analytics恢复seed；根代次重建导航草稿，确认点击待运行 |

## 演示路径（待有运行时执行）

1. 人群→全部/AI/手动→清除→展开01→折叠→详情→评分说明→返回。
2. 新建→输入无效数值→保存看错误→补有效条件→保存→查看详情→选择完成/依据不足/0覆盖任一模拟场景。
3. 01详情→编辑说明或规则→取消确认放弃；再编辑保存→V2→历史V1，核对旧规则与画像。
4. 字段管理→新增分类及属性→在新规则中选择→保存；编辑字段定义/停用，检查历史规则仍保留原定义。
5. 先重置→人群AI建议→有效建议→取消确认→再确认采纳→查看生成V2；旧建议不可采纳，已采纳不能重复。
6. 切审批Tab→查看人群版本变化提醒，原任务仍V1画像；数据Tab仍独立历史批次；右上演示工具→重置所有模块。

## 限制与后续接线

- 本地模拟；没有客户筛选、去重算法、AI、真实评分、发送、后端或持久化。
- 联合覆盖11000仅用于初始范围，新增重叠样本580有明确来源说明；修改后未知联合范围显示待统计。
- 完成识别固定借用人群01画像和8420覆盖，页面说明与规则无计算关系。依据不足覆盖未知；0覆盖无画像。每版本识别只完成一次，以免改写冻结历史。
- 当前C只有只读骨架，A没有代写选择器/确认执行；新建对象已可通过共享API读取。approvalStore只是现有单版本样本适配，C多版本任务必须按任务查快照。
- B/C/D均未在本次会话开发，无字段清单协商或跨模块发送闭环验收；不声称联合演示全部完成。现有方案更新及任务草稿提供最小校验入口，后续按领域增补。
- Figma MCP无编辑权限；用户授权后Chrome已定位总览节点并核对基本结构/尺寸，随后Computer Use工具拒绝当前URL并终止浏览器会话，二级画板及逐像素对照未完成。
- 安装iOS运行时后须补充表单取消、返回、四Tab切换、窄屏和大字体实际验收；真机和iOS17运行时也未验证。
- 代码通过独立提交交团队PR review；不自动合并main或他人分支。

## Git 交付状态

共享基础提交 `26118f2`；人群模块提交 `57d7f58`。均保存在 feature/audience。首次 `git push -u origin feature/audience` 返回 GitHub 403：现有认证账号 yguodong627-star 对 iceflying6397/demo 无写权限。随后用户明确要求给原仓库提交 PR，因此改用 yguodong627-star/demo Fork 作为分支上传来源，PR 目标仍为 iceflying6397/demo 的 main；不直接修改或合并原仓库 main。

交付附完整源码zip和Git bundle。具备权限的维护者可在原仓库执行：

```sh
git fetch /absolute/path/A-audience.bundle feature/audience:feature/audience
# 检查分支与以上构建/验证结果后，使用自己的仓库权限推送并发起团队PR。
```

实际执行应将路径替换为下载的 bundle 绝对路径。若本地已有同名开发分支，先检查差异，勿强制覆盖。构建产物、个人配置和凭据不在源码包内。
