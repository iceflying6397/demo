import Foundation

/// 无状态业务函数。A 在唯一会话事务内调用；B/C 共用资源和版本校验。
enum PlanValidation {
    static func errors(content: PlanContent, resources: [StoreResource], audiences: [Audience], on date: Date) -> [String] {
        var errors: [String] = []
        if content.normalized.message.isEmpty { errors.append("话术：请输入非空内容。") }
        if let id = content.resourceID {
            if let resource = resources.first(where: { $0.id == id }) {
                if let reason = resource.invalidReason(on: date) { errors.append("资源：\(resource.name)\(reason)，请替换或移除。") }
            } else { errors.append("资源：引用不可用，请重新选择。") }
        }
        if content.audienceIDs.contains(where: { id in !audiences.contains { $0.id == id } }) {
            errors.append("关联人群：存在不可用的人群，请重新选择。")
        }
        return errors
    }

    static func revision(request: PlanSaveRequest, plans: [MarketingPlan], metadata: [String: PlanMetadata],
                         resources: [StoreResource], audiences: [Audience], referenceDate: Date,
                         nextNumber: Int, now: Date, source: PlanChangeSource = .manual) throws -> PlanRevision? {
        let content = request.content.normalized
        let failures = errors(content: content, resources: resources, audiences: audiences, on: referenceDate)
        guard failures.isEmpty else { throw PlanValidationError(messages: failures) }
        let current = plans.first { $0.id == request.id }
        if let base = request.baseVersion {
            guard let current, current.version == base else { throw PlanValidationError("方案版本已变化，请退出后重新编辑。") }
            guard let info = metadata[current.id] else { throw PlanValidationError("方案元信息缺失，无法安全保存。") }
            if PlanContent(plan: current, resourceID: info.resourceID).normalized == content { return nil }
        } else {
            guard current == nil, !request.id.isEmpty else { throw PlanValidationError("此新建请求已提交或编号无效，请查看已有方案。") }
            guard nextNumber > 0, !plans.contains(where: { $0.number == nextNumber }) else {
                throw PlanValidationError("方案编号冲突，请重新分配。")
            }
        }
        let resource = resources.first { $0.id == content.resourceID }
        let plan = MarketingPlan(id: request.id, number: current?.number ?? nextNumber,
                                 purpose: content.purpose, customerStage: content.customerStage,
                                 version: (current?.version ?? 0) + 1, message: content.message,
                                 resourceSummary: resource?.name ?? "纯话术 · 无搭配资源",
                                 source: current?.source ?? request.creationSource, audienceIDs: content.audienceIDs)
        let info = PlanMetadata(resourceID: content.resourceID,
                                createdAt: metadata[request.id]?.createdAt ?? now, updatedAt: now)
        var changes: [String] = []
        if let current {
            if current.purpose != plan.purpose { changes.append("目的") }
            if current.customerStage != plan.customerStage { changes.append("适用客户") }
            if current.message != plan.message { changes.append("话术") }
            if metadata[current.id]?.resourceID != info.resourceID { changes.append("资源") }
            if Set(current.audienceIDs) != Set(plan.audienceIDs) { changes.append("关联人群") }
        }
        let summary = current == nil ? "创建方案" : "更新" + changes.joined(separator: "、")
        return .init(plan: plan, metadata: info,
                     snapshot: .init(plan: plan, metadata: info, resource: resource,
                                     resourceCheckedAt: referenceDate,
                                     changedAt: now, changeSource: current == nil ? .initial : source, summary: summary))
    }

    static func adoption(suggestion: PlanSuggestion, plans: [MarketingPlan], metadata: [String: PlanMetadata],
                         resources: [StoreResource], audiences: [Audience], referenceDate: Date, now: Date) throws -> PlanRevision {
        guard suggestion.status != .adopted else { throw PlanValidationError("建议已采纳，不能重复生成版本。") }
        guard let current = plans.first(where: { $0.id == suggestion.planID }), current.version == suggestion.baseVersion else {
            throw PlanValidationError("建议基础版本与当前版本不一致，不能覆盖最新编辑。")
        }
        let request = PlanSaveRequest(id: current.id, baseVersion: current.version,
                                      content: suggestion.proposed, creationSource: current.source)
        guard let revision = try revision(request: request, plans: plans, metadata: metadata, resources: resources,
                                          audiences: audiences, referenceDate: referenceDate, nextNumber: 0, now: now, source: .aiAdoption) else {
            throw PlanValidationError("建议与当前内容相同，不生成多余版本。")
        }
        return revision
    }

    static func allocation(configuration: TouchRuleConfiguration, plans: [MarketingPlan]) throws -> ABAllocation {
        guard (0...23).contains(configuration.hour), (0...59).contains(configuration.minute) else {
            throw PlanValidationError("生成时间：请选择有效的时、分。")
        }
        guard let first = plans.first(where: { $0.id == configuration.primaryPlanID }) else {
            throw PlanValidationError("方案 A：请选择可用方案。")
        }
        var groups = [ABAllocation.Group(planID: first.id, planVersion: first.version,
                                        percentage: configuration.primaryPercentage)]
        if let secondID = configuration.secondaryPlanID {
            guard let second = plans.first(where: { $0.id == secondID }) else { throw PlanValidationError("方案 B：请选择可用方案。") }
            guard (1...99).contains(configuration.primaryPercentage) else { throw PlanValidationError("双方案比例各为 1…99%。") }
            groups.append(.init(planID: second.id, planVersion: second.version, percentage: 100 - configuration.primaryPercentage))
        }
        guard let result = ABAllocation(groups: groups) else {
            throw PlanValidationError("分配：单方案须为 100%；双方案须不同且比例合计 100%。")
        }
        return result
    }

    static func rule(id: String, baseRevision: Int?, configuration: TouchRuleConfiguration,
                     rules: [TouchRule], plans: [MarketingPlan], nextNumber: Int, now: Date) throws -> TouchRule {
        _ = try allocation(configuration: configuration, plans: plans)
        let current = rules.first { $0.id == id }
        if let baseRevision {
            guard let current, current.revision == baseRevision else { throw PlanValidationError("规则已变化，请重新打开编辑。") }
            guard current.configuration.kind == configuration.kind else { throw PlanValidationError("已有规则不能更改类型，请新建规则。") }
            if current.configuration == configuration { return current }
        } else {
            guard current == nil, !id.isEmpty, nextNumber > 0, !rules.contains(where: { $0.number == nextNumber }) else {
                throw PlanValidationError("规则已保存或编号冲突，请重新打开列表。")
            }
        }
        return .init(id: id, number: current?.number ?? nextNumber, revision: (current?.revision ?? 0) + 1,
                     configuration: configuration, updatedAt: now)
    }

    static func preview(rule: TouchRule, plans: [MarketingPlan], metadata: [String: PlanMetadata],
                        resources: [StoreResource], audiences: [Audience], ranges: [PlanRuleRange],
                        referenceDate: Date) throws -> PlanRulePreview {
        let configuration = rule.configuration
        let allocation = try allocation(configuration: configuration, plans: plans)
        guard let range = ranges.first(where: {
            $0.kind == configuration.kind && ($0.kind == .birthday || $0.period == configuration.period)
        }), let audience = audiences.first(where: { $0.id == range.audienceID }),
              range.expectedReach >= 0, range.expectedReach <= audience.memberCount else {
            throw PlanValidationError("预览范围不可用，请核对共享样本和人群。")
        }
        var snapshots: [PlanVersionSnapshot] = []
        for group in allocation.groups {
            guard let plan = plans.first(where: { $0.id == group.planID }), let info = metadata[plan.id] else {
                throw PlanValidationError("方案内容或元信息缺失。")
            }
            let content = PlanContent(plan: plan, resourceID: info.resourceID)
            let failures = errors(content: content, resources: resources, audiences: audiences, on: referenceDate)
            guard failures.isEmpty else { throw PlanValidationError(messages: failures) }
            snapshots.append(.init(plan: plan, metadata: info, resource: resources.first { $0.id == info.resourceID },
                                   resourceCheckedAt: referenceDate,
                                   changedAt: info.updatedAt, changeSource: .initial, summary: "规则预览时内容"))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3600) ?? .gmt
        let components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        guard let year = components.year, let month = components.month, let day = components.day else {
            throw PlanValidationError("演示参考日不可用。")
        }
        let cycle = String(format: "%04d-%02d-%02d", year, month, day)
        let cutoff = configuration.kind == .followUp ? calendar.date(byAdding: .month, value: -configuration.period.rawValue, to: referenceDate) : nil
        return .init(rule: rule, referenceDate: referenceDate, cycleID: cycle, audience: audience,
                     expectedReach: range.expectedReach, scopeSummary: range.summary, cutoffDate: cutoff,
                     allocation: allocation, plans: snapshots)
    }

    /// C 在实际追加 pending 任务的同一个 MainActor 事务内调用，不能仅依赖按钮禁用。
    static func validateGeneration(preview: PlanRulePreview, current: PlanRulePreview,
                                   generations: [PlanRuleGeneration]) throws {
        guard preview == current else { throw PlanValidationError("规则、方案或范围已变化，请重新预览。") }
        guard current.rule.configuration.isEnabled else { throw PlanValidationError("规则已禁用。") }
        guard !generations.contains(where: { $0.id == current.deduplicationKey }) else {
            throw PlanValidationError("本周期已生成，请到发送审批查看原任务。")
        }
        guard current.expectedReach > 0 else { throw PlanValidationError("没有匹配客户，不生成空任务。") }
        guard current.allocation.expectedCounts(total: current.expectedReach).allSatisfy({ $0 > 0 }) else {
            throw PlanValidationError("分配后有空组，请调整比例或使用单方案。")
        }
    }
}
