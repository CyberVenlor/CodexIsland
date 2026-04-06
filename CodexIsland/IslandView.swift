import AppKit
import SwiftUI

struct IslandView: View {
    @ObservedObject var controller: IslandController
    @EnvironmentObject private var sessionController: CodexSessionController
    @EnvironmentObject private var settingsStore: SettingsConfigStore
    private let shellStrokeWidth: CGFloat = 1.2

    private var state: IslandPresentationState {
        controller.presentationState
    }

    private var shellStyle: IslandShellStyle {
        IslandShellStyle.forState(state)
    }

    private var canvasSize: CGSize {
        IslandShellStyle.canvasSize
    }

    private var language: AppLanguage {
        settingsStore.config.appLanguage
    }

    var body: some View {
        ZStack {
            islandBody
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .top)
        .onAppear {
            controller.updateApprovalPresentation(hasPendingApproval: sessionController.hasPendingApprovals)
        }
        .onChange(of: sessionController.pendingApprovalToolCall?.id) { newValue in
            controller.updateApprovalPresentation(hasPendingApproval: newValue != nil)
        }
        .onChange(of: sessionController.sessionEndedNotification?.id) { newValue in
            guard newValue != nil else { return }
            controller.presentSessionEndedPanel()
        }
        .contextMenu {
            ForEach(CollapsedIslandMode.allCases) { mode in
                Button(mode.title(in: language)) {
                    controller.collapsedMode = mode
                }
            }
        }
    }

    private var islandBody: some View {
        ZStack {
            shell
            content
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .top)
        .background(alignment: .top) {
            hoverTrackingArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var hoverTrackingArea: some View {
        HoverTrackingView { isHovering in
            controller.handleHoverChange(isHovering)
        }
            .frame(
                width: shellStyle.size.width,
                height: shellStyle.size.height + IslandOverlayLayout.topEdgeHoverTolerance
            )
    }

    private var shell: some View {
        AnimatedNotchShape(
            shellWidth: shellStyle.size.width,
            shellHeight: shellStyle.size.height,
            topRadius: shellStyle.topRadius,
            bottomRadius: shellStyle.bottomRadius
        )
        .fill(.black.opacity(shellStyle.backgroundOpacity))
        .overlay {
            AnimatedNotchShape(
                shellWidth: shellStyle.size.width,
                shellHeight: shellStyle.size.height,
                topRadius: shellStyle.topRadius,
                bottomRadius: shellStyle.bottomRadius
            )
            .stroke(Color.white.opacity(shellStyle.strokeOpacity), lineWidth: shellStrokeWidth)
        }
    }

    private var content: some View {
        IslandContentView(
            state: state,
            controller: controller,
            sessionController: sessionController
        )
    }
}

private struct HoverTrackingView: NSViewRepresentable {
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> MouseTrackingNSView {
        let view = MouseTrackingNSView()
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: MouseTrackingNSView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
        nsView.updateTrackingAreas()
    }
}

private final class MouseTrackingNSView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var hoverMonitorTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea

        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
    }

    override func mouseMoved(with event: NSEvent) {
        reconcileHoverState()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateLayer() {
        super.updateLayer()
        reconcileHoverState()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func reconcileHoverState() {
        guard let window else {
            setHovering(false)
            return
        }

        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let hoverBounds = bounds.insetBy(dx: 0, dy: -IslandOverlayLayout.topEdgeHoverTolerance)
        setHovering(hoverBounds.contains(location))
    }

    private func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else {
            return
        }

        isHovering = hovering
        updateHoverMonitorTimer()
        onHoverChanged?(hovering)
    }

    private func updateHoverMonitorTimer() {
        hoverMonitorTimer?.invalidate()
        hoverMonitorTimer = nil

        guard isHovering else {
            return
        }

        hoverMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            self?.reconcileHoverState()
        }
    }

    deinit {
        hoverMonitorTimer?.invalidate()
    }
}

struct IslandContentView: View {
    let state: IslandPresentationState
    @ObservedObject var controller: IslandController
    @ObservedObject var sessionController: CodexSessionController
    @EnvironmentObject private var settingsStore: SettingsConfigStore

    private var l10n: AppLocalization {
        AppLocalization(language: settingsStore.config.appLanguage)
    }

    private let detailedSize = IslandShellStyle.forState(.collapsed(.detailed)).size

    private var isExpanded: Bool {
        if case .expanded(_) = state {
            return true
        }
        return false
    }

    private var expandedSize: CGSize {
        IslandShellStyle.forState(state).size
    }

    private var isDetailedCollapsed: Bool {
        if case .collapsed(.detailed) = state {
            return true
        }
        return false
    }

    private var collapsedRunningSessionCountText: String {
        let count = sessionController.runningSessionCount
        if count > 9 {
            return ">9"
        }

        return String(format: "%02d", count)
    }

    private var collapsedActivityColor: Color {
        sessionController.runningSessionCount > 0 ? .green : .blue
    }

    var body: some View {
        ZStack(alignment: .top) {
            collapsedContent
            expandedContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .mask {
            AnimatedNotchShape(
                shellWidth: IslandShellStyle.forState(state).size.width,
                shellHeight: IslandShellStyle.forState(state).size.height,
                topRadius: IslandShellStyle.forState(state).topRadius,
                bottomRadius: IslandShellStyle.forState(state).bottomRadius
            )
        }
    }

    private var collapsedContent: some View {
        ZStack {
            Image(systemName: "waveform")
                .font(.body.weight(.semibold))
                .foregroundStyle(collapsedActivityColor)
                .frame(width: 24)
                .offset(x: -100)

            Text(collapsedRunningSessionCountText)
                .foregroundStyle(collapsedActivityColor)
                .offset(x: 100)
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 0)
        .frame(width: detailedSize.width, height: detailedSize.height, alignment: .center)
        .opacity(isDetailedCollapsed ? 1 : 0)
        .blur(radius: isDetailedCollapsed ? 0 : 14)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            expandedHeader
            expandedDetails
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
        .opacity(isExpanded ? 1 : 0)
        .blur(radius: isExpanded ? 0 : 18)
    }

    private var isSettingsPanelActive: Bool {
        controller.activePanel == .settings
    }

    private var approvalPanelStatus: ApprovalPanelStatus? {
        if case .approval(let status) = controller.activePanel {
            return status
        }
        return nil
    }

    private var isApprovalPanelActive: Bool {
        approvalPanelStatus != nil
    }

    private var isSessionEndedPanelActive: Bool {
        controller.activePanel == .sessionEnded
    }

    private var settingsIconOpacity: Double {
        isSettingsPanelActive ? 0 : 1
    }

    private var closeIconOpacity: Double {
        isSettingsPanelActive ? 1 : 0
    }

    private var expandedHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expandedTitle)
                    .font(.headline)
                    .foregroundStyle(.white)

                if let subtitle = expandedSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                } else if !isSettingsPanelActive {
                    Text(l10n.trackedSessions(sessionController.sessions.count))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            Spacer()

            if !isApprovalPanelActive && !isSessionEndedPanelActive {
                Button {
                    controller.toggleSettingsPanel()
                } label: {
                    Image(systemName: isSettingsPanelActive ? "xmark.circle.fill" : "gearshape.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .opacity(isSettingsPanelActive ? closeIconOpacity : settingsIconOpacity)
                        .animation(.linear(duration: 0.16), value: isSettingsPanelActive)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help(
                    isSettingsPanelActive
                    ? l10n.text("Close Settings", chinese: "关闭设置")
                    : l10n.text("Open Settings", chinese: "打开设置")
                )
            }
        }
        .padding(.bottom, 12)
    }

    private var expandedTitle: String {
        if isSettingsPanelActive {
            return l10n.text("Settings", chinese: "设置")
        }
        if isSessionEndedPanelActive {
            return l10n.text("Session Complete", chinese: "Session 已结束")
        }
        if let status = approvalPanelStatus {
            return status == .pending
                ? l10n.text("Tool Approval", chinese: "工具审批")
                : l10n.text("Approved", chinese: "已批准")
        }
        return l10n.text("Codex Sessions", chinese: "Codex 会话")
    }

    private var expandedSubtitle: String? {
        guard let status = approvalPanelStatus else {
            if isSessionEndedPanelActive {
                return l10n.text("A Codex session just finished", chinese: "一个 Codex session 刚刚结束")
            }
            return nil
        }

        switch status {
        case .pending:
            return l10n.text("Unsafe tool requires manual approval", chinese: "高风险工具需要手动审批")
        case .completed:
            return l10n.text("Approval queue cleared", chinese: "审批队列已清空")
        }
    }

    @ViewBuilder
    private var expandedDetails: some View {
        if controller.activePanel == .settings {
            SettingsPanelView()
                .environmentObject(settingsStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if controller.activePanel == .sessionEnded {
            SessionEndedPanelView()
                .environmentObject(sessionController)
                .environmentObject(settingsStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if let status = approvalPanelStatus {
            ApprovalPanelView(status: status)
                .environmentObject(sessionController)
                .environmentObject(settingsStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            CodexSessionListView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct SessionEndedPanelView: View {
    @EnvironmentObject private var sessionController: CodexSessionController
    @EnvironmentObject private var settingsStore: SettingsConfigStore

    private var l10n: AppLocalization {
        AppLocalization(language: settingsStore.config.appLanguage)
    }

    var body: some View {
        let notification = sessionController.sessionEndedNotification

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: 42, height: 42)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(notification?.title ?? l10n.text("Completed Session", chinese: "已完成 Session"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(notification?.projectName ?? "")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Text(l10n.text(
                "The session has finished and returned a final response.",
                chinese: "这个 session 已经结束，并返回了最终结果。"
            ))
            .font(.caption)
            .foregroundStyle(.white.opacity(0.72))
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ApprovalPanelView: View {
    let status: ApprovalPanelStatus
    @EnvironmentObject private var sessionController: CodexSessionController
    @EnvironmentObject private var settingsStore: SettingsConfigStore

    private var l10n: AppLocalization {
        AppLocalization(language: settingsStore.config.appLanguage)
    }

    var body: some View {
        Group {
            switch status {
            case .pending:
                if let toolCall = sessionController.pendingApprovalToolCall {
                    pendingView(toolCall)
                } else {
                    completionView
                }
            case .completed:
                completionView
            }
        }
    }

    private func pendingView(_ toolCall: CodexToolCall) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                approvalLabel(l10n.text("Tool", chinese: "工具"), value: toolCall.toolName ?? toolCall.toolUseID ?? "-")

                if let toolUseID = toolCall.toolUseID {
                    approvalLabel("ID", value: toolUseID, monospaced: true)
                }

                if let command = toolCall.toolCommand {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(l10n.text("Command", chinese: "命令"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.65))

                        Text(command)
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.9))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .lineLimit(4)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }

            HStack(spacing: 10) {
                Button(l10n.text("Deny", chinese: "拒绝")) {
                    sessionController.deny(toolCall)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.8))

                Button(l10n.text("Approve", chinese: "批准")) {
                    sessionController.approve(toolCall)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var completionView: some View {
        VStack(spacing: 14) {
            ApprovalCompletionGlyph()

            Text(l10n.text("Approval Complete", chinese: "审批完成"))
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                decisionCountPill(
                    label: l10n.text("Approved", chinese: "已批准"),
                    count: sessionController.approvalDecisionCounts.approved,
                    color: .green
                )
                decisionCountPill(
                    label: l10n.text("Blocked", chinese: "已拦截"),
                    count: sessionController.approvalDecisionCounts.denied,
                    color: .red
                )
            }

            Text(l10n.text("All pending unsafe tools have been processed.", chinese: "所有待处理的高风险工具都已经处理完成。"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func approvalLabel(_ title: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.65))

            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private func decisionCountPill(label: String, count: Int, color: Color) -> some View {
        let accentColor: Color = count == 0 ? .gray : color

        return VStack(spacing: 4) {
            Text("\(count)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accentColor.opacity(0.28), lineWidth: 1)
        }
    }
}

private struct ApprovalCompletionGlyph: View {
    @State private var trimEnd: CGFloat = 0
    @State private var scale: CGFloat = 0.84
    @State private var opacity: Double = 0.35

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 3)
                .frame(width: 46, height: 46)

            CheckmarkShape()
                .trim(from: 0, to: trimEnd)
                .stroke(
                    Color.green,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 28, height: 24)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                scale = 1
                opacity = 1
            }
            withAnimation(.easeOut(duration: 0.28).delay(0.08)) {
                trimEnd = 1
            }
        }
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.midY + rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.40, y: rect.maxY - rect.height * 0.14))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.16))
        return path
    }
}

struct CodexSessionListView: View {
    @EnvironmentObject private var sessionController: CodexSessionController
    @EnvironmentObject private var settingsStore: SettingsConfigStore
    private let sessionCornerRadius: CGFloat = 16
    private let toolCallCornerRadius: CGFloat = 12
    private let sessionStackAnimation = Animation.spring(response: 0.42, dampingFraction: 0.86)

    private var l10n: AppLocalization {
        AppLocalization(language: settingsStore.config.appLanguage)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(sessionController.sessions) { session in
                    sessionRow(session)
                        .transition(.asymmetric(
                            insertion: .modifier(
                                active: SessionInsertTransition(opacity: 0, blurRadius: 18, offsetY: -24, scale: 0.97),
                                identity: SessionInsertTransition(opacity: 1, blurRadius: 0, offsetY: 0, scale: 1)
                            ),
                            removal: .opacity
                        ))
                }
            }
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .background(Color.clear)
        .overlay {
            if sessionController.sessions.isEmpty {
                ContentUnavailableView(
                    l10n.text("No Codex Sessions", chinese: "没有 Codex 会话"),
                    systemImage: "bolt.slash",
                    description: Text(l10n.text(
                        "Only sessions received after this app launch are tracked.",
                        chinese: "只会跟踪本次启动应用后收到的会话。"
                    ))
                )
            }
        }
        .animation(sessionStackAnimation, value: sessionController.sessions.map(\.id))
    }

    @ViewBuilder
    private func sessionRow(_ session: CodexSessionGroup) -> some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(2)

                Spacer()

                HStack(spacing: 8) {
                    if canOpen(session) {
                        Button {
                            _ = sessionController.openSession(session)
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)

                    }

                    Text(session.projectName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Text(l10n.localizedSessionState(session.state))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(stateColor(for: session.state))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(stateColor(for: session.state).opacity(0.15), in: Capsule())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            if !session.toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(session.toolCalls) { toolCall in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(l10n.toolLabel(name: toolCall.toolName ?? toolCall.toolUseID ?? "-"))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let toolUseID = toolCall.toolUseID {
                                Text(l10n.toolUseIDLabel(toolUseID))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }

                            if let toolCommand = toolCall.toolCommand {
                                Text(toolCommand)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }

                            if toolCall.requiresApproval {
                                HStack {
                                    Button(l10n.text("Approve", chinese: "批准")) {
                                        sessionController.approve(toolCall)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button(l10n.text("Deny", chinese: "拒绝")) {
                                        sessionController.deny(toolCall)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            } else if let approvalStatus = toolCall.approvalStatus {
                                Text(l10n.approvalStatusLabel(approvalStatus))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .background(
                            Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: toolCallCornerRadius, style: .continuous)
                        )
                    }
                }
            }

            if let lastAssistantMessage = session.lastAssistantMessage, !lastAssistantMessage.isEmpty {
                Text(lastAssistantMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            Color.white.opacity(0.08),
            in: RoundedRectangle(cornerRadius: sessionCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: sessionCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }

        if canOpen(session) {
            content
                .contentShape(RoundedRectangle(cornerRadius: sessionCornerRadius, style: .continuous))
                .onTapGesture {
                    _ = sessionController.openSession(session)
                }
        } else {
            content
        }
    }

    private func stateColor(for state: CodexSessionState) -> Color {
        switch state {
        case .running:
            return .green
        case .idle:
            return .orange
        case .completed:
            return .blue
        case .unknown:
            return .gray
        }
    }

    private func canOpen(_ session: CodexSessionGroup) -> Bool {
        switch session.source {
        case .cli, .vscode:
            return true
        case .other, .none:
            return false
        }
    }
}

private struct SessionInsertTransition: ViewModifier {
    let opacity: Double
    let blurRadius: CGFloat
    let offsetY: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: blurRadius)
            .scaleEffect(scale, anchor: .top)
            .offset(y: offsetY)
    }
}

struct IslandListRow: View {
    let item: IslandListItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
