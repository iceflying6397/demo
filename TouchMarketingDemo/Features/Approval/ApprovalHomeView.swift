import SwiftUI

enum ApprovalInbox: String, CaseIterable, Identifiable {
    case pending = "待审批"
    case sent = "已发送"
    var id: String { rawValue }
}

enum ApprovalPendingFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case open = "待处理"
    case deferred = "稍后"
    var id: String { rawValue }
}

enum ApprovalSentFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case waiting = "等待发送"
    case sending = "发送中"
    case succeeded = "发送成功"
    case partiallyFailed = "部分失败"
    case failed = "发送失败"
    var id: String { rawValue }
}

struct ApprovalHomeView: View {
    let store: MockDataStore
    @Environment(DemoSession.self) private var session
    @State private var inbox: ApprovalInbox = .pending
    @State private var pendingFilter: ApprovalPendingFilter = .all
    @State private var sentFilter: ApprovalSentFilter = .all
    @State private var drafts: [String: ApprovalFormDraft] = [:]

    var body: some View {
        let _ = store.approvalTasks.count
        DemoPage {
            DemoIntro(description: "核对本次发给谁、用哪套方案、各占多少。发送是本地模拟。")
            Picker("分组", selection: $inbox) {
                ForEach(ApprovalInbox.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            ApprovalFilterBar(options: filterTitles, selection: selectedFilterTitle, onSelect: selectFilter)
            let visible = visibleTasks()
            if visible.isEmpty {
                DemoEmptyState(title: emptyTitle, message: emptyMessage)
            } else {
                ForEach(visible) { task in
                    ApprovalTaskCard(taskID: task.id, draft: draftBinding(for: task))
                        .accessibilityIdentifier("approval.\(task.id)")
                }
            }
            NavigationLink("处理记录") { ApprovalRecordListView() }
                .buttonStyle(DemoSecondaryButtonStyle())
            ApprovalDemoControls()
        }
        .navigationTitle("发送审批")
        .onChange(of: session.resetGeneration) { _, _ in
            drafts = [:]
            inbox = .pending
            pendingFilter = .all
            sentFilter = .all
        }
    }

    private var filterTitles: [String] {
        switch inbox {
        case .pending: ApprovalPendingFilter.allCases.map(\.rawValue)
        case .sent: ApprovalSentFilter.allCases.map(\.rawValue)
        }
    }

    private var selectedFilterTitle: String {
        switch inbox {
        case .pending: pendingFilter.rawValue
        case .sent: sentFilter.rawValue
        }
    }

    private func selectFilter(_ title: String) {
        switch inbox {
        case .pending:
            pendingFilter = ApprovalPendingFilter(rawValue: title) ?? .all
        case .sent:
            sentFilter = ApprovalSentFilter(rawValue: title) ?? .all
        }
    }

    private func visibleTasks() -> [ApprovalTask] {
        session.tasks.filter { task in
            switch inbox {
            case .pending:
                switch pendingFilter {
                case .all: return task.approvalStatus == .pending || task.approvalStatus == .deferred
                case .open: return task.approvalStatus == .pending
                case .deferred: return task.approvalStatus == .deferred
                }
            case .sent:
                guard task.approvalStatus == .confirmed, let delivery = task.deliveryStatus else { return false }
                switch sentFilter {
                case .all: return true
                case .waiting: return delivery == .waiting
                case .sending: return delivery == .sending
                case .succeeded: return delivery == .succeeded
                case .partiallyFailed: return delivery == .partiallyFailed
                case .failed: return delivery == .failed
                }
            }
        }
        .sorted { $0.number < $1.number }
    }

    private var pendingTotal: Int {
        session.tasks.filter { $0.approvalStatus == .pending || $0.approvalStatus == .deferred }.count
    }

    private var sentTotal: Int {
        session.tasks.filter { $0.approvalStatus == .confirmed && $0.deliveryStatus != nil }.count
    }

    private var emptyTitle: String {
        switch inbox {
        case .pending: pendingTotal == 0 ? "没有待审批任务" : "这个筛选没有任务"
        case .sent: sentTotal == 0 ? "没有已发送任务" : "这个筛选没有任务"
        }
    }

    private var emptyMessage: String {
        switch inbox {
        case .pending:
            pendingTotal == 0
                ? "被拒绝的任务在处理记录里。可以重置演示，或用规则再生成一条。"
                : "换一个筛选还能看到其他待审批任务。这里不会放一张假的确认卡片。"
        case .sent:
            sentTotal == 0
                ? "确认模拟发送后，任务会出现在这里，包括等待发送。"
                : "换一个执行状态筛选。等待发送也属于已发送。"
        }
    }

    private func draftBinding(for task: ApprovalTask) -> Binding<ApprovalFormDraft> {
        Binding(
            get: { drafts[task.id] ?? .from(task: task) },
            set: { drafts[task.id] = $0 }
        )
    }
}

private struct ApprovalFilterBar: View {
    let options: [String]
    let selection: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DemoTheme.Spacing.small) {
                ForEach(options, id: \.self) { option in
                    Button(option) { onSelect(option) }
                        .font(DemoTheme.Typography.body)
                        .padding(.horizontal, DemoTheme.Spacing.medium)
                        .frame(minHeight: 44)
                        .background(option == selection ? DemoTheme.ColorToken.black : DemoTheme.ColorToken.white,
                                    in: RoundedRectangle(cornerRadius: DemoTheme.Radius.button))
                        .foregroundStyle(option == selection ? DemoTheme.ColorToken.white : DemoTheme.ColorToken.primaryText)
                        .overlay(RoundedRectangle(cornerRadius: DemoTheme.Radius.button).stroke(DemoTheme.ColorToken.border))
                }
            }
        }
    }
}

struct ApprovalTaskCard: View {
    let taskID: String
    @Binding var draft: ApprovalFormDraft
    @Environment(DemoSession.self) private var session
    @State private var message: String?

    var body: some View {
        if let task = session.task(id: taskID) {
            DemoCard {
                Text(task.displayName).font(DemoTheme.Typography.heading)
                DemoValueRow(title: "来源", value: task.sourceMark)
                DemoValueRow(title: "说明", value: task.originSummary)
                if task.approvalStatus == .confirmed {
                    sentBody(task)
                } else {
                    pendingBody(task)
                }
                if let message {
                    Text(message)
                        .font(DemoTheme.Typography.caption)
                        .foregroundStyle(DemoTheme.ColorToken.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func pendingBody(_ task: ApprovalTask) -> some View {
        audienceBlock(task)
        ForEach(Array(task.allocation.groups.enumerated()), id: \.offset) { index, group in
            let plan = session.planRevision(id: group.planID, version: group.planVersion)
            DemoValueRow(title: "\(ApprovalDisplay.letter(index)) 组目的", value: plan?.purpose.rawValue ?? "—")
            DemoValueRow(title: "\(ApprovalDisplay.letter(index)) 组客户", value: plan?.customerStage.rawValue ?? "—")
        }
        ApprovalAllocationEditor(
            draft: $draft,
            reach: session.knownReach(audienceID: draft.audienceID, version: draft.audienceVersion),
            recommendation: recommendation(task),
            planName: planName,
            onRestore: { restore(task) },
            onAddSecond: addSecond,
            onRemoveLast: removeLast
        )
        if !draft.matches(task) {
            Text("这是未保存草稿。确认发送仍使用已保存的 \(savedPercent(task))。")
                .font(DemoTheme.Typography.caption)
                .foregroundStyle(DemoTheme.ColorToken.secondaryText)
            Button("保存草稿") { save(task) }
                .buttonStyle(DemoPrimaryButtonStyle())
            Button("取消草稿") {
                draft = .from(task: task)
                message = "草稿已取消，任务仍是已保存配置。"
            }
            .buttonStyle(DemoSecondaryButtonStyle())
        }
        ApprovalPendingActions(taskID: task.id, hasUnsavedDraft: !draft.matches(task))
        NavigationLink("查看任务详情") { ApprovalDetailView(taskID: task.id) }
            .buttonStyle(DemoSecondaryButtonStyle())
    }

    @ViewBuilder
    private func sentBody(_ task: ApprovalTask) -> some View {
        if let snapshot = session.snapshot(for: task.id) {
            DemoValueRow(title: "人群", value: "\(snapshot.audienceDisplayName) V\(snapshot.audienceVersion)")
            DemoValueRow(title: "本次预计", value: "\(DemoFormat.count(snapshot.expectedReach)) 人")
            ForEach(Array(snapshot.groups.enumerated()), id: \.offset) { index, group in
                DemoValueRow(
                    title: "\(ApprovalDisplay.letter(index)) \(group.displayName)",
                    value: "\(group.percentage)% · \(DemoFormat.count(group.allocatedCount)) 人"
                )
            }
        }
        DemoValueRow(title: "执行", value: task.deliveryStatus?.rawValue ?? "—")
        NavigationLink("查看发送结果") { ApprovalResultView(taskID: task.id) }
            .buttonStyle(DemoPrimaryButtonStyle())
    }

    private func audienceBlock(_ task: ApprovalTask) -> some View {
        let audience = session.audienceRevision(id: task.audienceID, version: task.audienceVersion)
        return VStack(alignment: .leading, spacing: DemoTheme.Spacing.medium) {
            DemoValueRow(title: "状态", value: task.approvalStatus.rawValue)
            DemoValueRow(title: "人群", value: audience?.displayName ?? "人群不可用")
            DemoValueRow(title: "人群版本", value: "V\(task.audienceVersion)")
            DemoValueRow(title: "人群覆盖", value: audience.map { "\(DemoFormat.count($0.memberCount)) 人" } ?? "不可用")
            DemoValueRow(title: "本次预计", value: ApprovalDisplay.reachText(for: task))
            Text("覆盖人数不是本次触达人数。")
                .font(DemoTheme.Typography.caption)
                .foregroundStyle(DemoTheme.ColorToken.secondaryText)
            if let audience {
                ForEach(Array(audience.scores.prefix(3))) { score in
                    DemoValueRow(title: score.dimension.rawValue, value: score.displayValue)
                }
            }
        }
    }

    private func save(_ task: ApprovalTask) {
        let reach = session.knownReach(audienceID: draft.audienceID, version: draft.audienceVersion)
        if let error = draft.validationMessage(reach: reach) {
            message = error
            return
        }
        guard let allocation = draft.makeAllocation() else {
            message = "分配无效，不能保存。"
            return
        }
        let result = session.saveAdjustment(
            taskID: task.id, audienceID: draft.audienceID,
            audienceVersion: draft.audienceVersion, allocation: allocation
        )
        message = result.message
        if case .saved = result, let updated = session.task(id: task.id) {
            draft = .from(task: updated)
        }
    }

    private func restore(_ task: ApprovalTask) {
        draft.slots = task.recommendedAllocation.groups.map { .init(planID: $0.planID, planVersion: $0.planVersion) }
        draft.primaryPercentText = task.recommendedAllocation.groups.first.map { String($0.percentage) } ?? "100"
        message = "草稿已回到推荐比例。保存后才会写入任务。"
    }

    private func addSecond() {
        guard draft.slots.count == 1, let first = draft.slots.first else { return }
        guard let other = session.plans.first(where: { $0.id != first.planID }) else {
            message = "没有另一套可添加的方案。"
            return
        }
        draft.slots.append(.init(planID: other.id, planVersion: other.version))
        draft.primaryPercentText = "50"
        message = "已加入第二套方案，初始 50%／50%。保存后才会写入任务。"
    }

    private func removeLast() {
        guard draft.slots.count > 1 else { return }
        draft.slots.removeLast()
        draft.primaryPercentText = "100"
        message = "已保留一套方案，比例为 100%。保存后才会写入任务。"
    }

    private func planName(_ id: String, _ version: Int) -> String {
        session.planRevision(id: id, version: version)?.displayName ?? "方案不可用"
    }

    private func recommendation(_ task: ApprovalTask) -> String {
        task.recommendedAllocation.groups.enumerated().map { index, group in
            "\(ApprovalDisplay.letter(index)) \(group.percentage)%"
        }.joined(separator: "／")
    }

    private func savedPercent(_ task: ApprovalTask) -> String {
        task.allocation.groups.map { "\($0.percentage)%" }.joined(separator: "／")
    }
}

struct ApprovalPendingActions: View {
    let taskID: String
    let hasUnsavedDraft: Bool
    @Environment(DemoSession.self) private var session
    @State private var confirmDefer = false
    @State private var showReject = false
    @State private var notice: String?

    var body: some View {
        if let task = session.task(id: taskID),
           task.approvalStatus == .pending || task.approvalStatus == .deferred {
            NavigationLink("查看并调整") { ApprovalTaskEditView(taskID: taskID) }
                .buttonStyle(DemoPrimaryButtonStyle())
            NavigationLink("确认发送") {
                ApprovalConfirmView(taskID: taskID, hasUnsavedDraft: hasUnsavedDraft)
            }
            .buttonStyle(DemoPrimaryButtonStyle())
            Button("稍后处理") { confirmDefer = true }
                .buttonStyle(DemoSecondaryButtonStyle())
            Button("拒绝") { showReject = true }
                .buttonStyle(DemoSecondaryButtonStyle())
            if let notice {
                Text(notice)
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
            }
            Color.clear.frame(width: 0, height: 0)
                .confirmationDialog("稍后处理这条任务？", isPresented: $confirmDefer, titleVisibility: .visible) {
                    Button("确认稍后处理") { notice = session.deferTask(taskID: taskID).message }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("任务仍留在待审批，不会发送。")
                }
                .sheet(isPresented: $showReject) {
                    ApprovalRejectSheet(taskID: taskID)
                }
        }
    }
}

struct ApprovalRejectSheet: View {
    let taskID: String
    @Environment(DemoSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var message: String?

    var body: some View {
        DemoPage {
            if let task = session.task(id: taskID) {
                Text(task.displayName).font(DemoTheme.Typography.title)
                Text("拒绝后不发送，也不会变成发送成功。任务从待审批移除，处理记录里还能看到原配置。")
                    .font(DemoTheme.Typography.body)
                Text("人群 \(session.audienceRevision(id: task.audienceID, version: task.audienceVersion)?.displayName ?? "不可用") · \(ApprovalDisplay.reachText(for: task))")
                    .font(DemoTheme.Typography.body)
            }
            TextField("拒绝原因，可以不填", text: $reason)
                .textFieldStyle(.roundedBorder)
            if let message {
                Text(message)
                    .font(DemoTheme.Typography.caption)
                    .foregroundStyle(DemoTheme.ColorToken.secondaryText)
            }
            Button("确认拒绝") {
                let result = session.rejectTask(taskID: taskID, reason: reason)
                message = result.message
                if !result.isFailure { dismiss() }
            }
            .buttonStyle(DemoPrimaryButtonStyle())
            Button("取消") { dismiss() }
                .buttonStyle(DemoSecondaryButtonStyle())
        }
    }
}
