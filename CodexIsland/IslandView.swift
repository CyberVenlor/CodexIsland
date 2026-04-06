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
        IslandShellStyle.forState(
            state,
            approvalPanelShowsDenyReason: controller.approvalPanelShowsDenyReason
        )
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
            controller.updateTransientPresentationSettings(
                sessionEndedDuration: TimeInterval(settingsStore.config.completedIslandDisplayDuration),
                suspiciousDuration: TimeInterval(settingsStore.config.suspiciousIslandDisplayDuration)
            )
        }
        .onChange(of: sessionController.pendingApprovalToolCall?.id) { newValue in
            controller.updateApprovalPresentation(hasPendingApproval: newValue != nil)
        }
        .onChange(of: sessionController.sessionEndedNotification?.id) { newValue in
            guard newValue != nil else { return }
            controller.presentSessionEndedPanel()
        }
        .onChange(of: sessionController.suspiciousSessionNotification?.id) { newValue in
            guard newValue != nil else { return }
            controller.presentSuspiciousSessionPanel()
        }
        .onChange(of: settingsStore.config.completedIslandDisplayDuration) { newValue in
            controller.updateTransientPresentationSettings(
                sessionEndedDuration: TimeInterval(newValue),
                suspiciousDuration: TimeInterval(settingsStore.config.suspiciousIslandDisplayDuration)
            )
        }
        .onChange(of: settingsStore.config.suspiciousIslandDisplayDuration) { newValue in
            controller.updateTransientPresentationSettings(
                sessionEndedDuration: TimeInterval(settingsStore.config.completedIslandDisplayDuration),
                suspiciousDuration: TimeInterval(newValue)
            )
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
        .allowsHoverAfterExit(controller.hoverResetRequiresExit == false)
        .id(controller.hoverResetToken)
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
    private var allowsHoverWithoutExit = true

    init(onHoverChanged: @escaping (Bool) -> Void) {
        self.onHoverChanged = onHoverChanged
    }

    func makeNSView(context: Context) -> MouseTrackingNSView {
        let view = MouseTrackingNSView()
        view.onHoverChanged = onHoverChanged
        view.allowsHoverWithoutExit = allowsHoverWithoutExit
        return view
    }

    func updateNSView(_ nsView: MouseTrackingNSView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
        nsView.allowsHoverWithoutExit = allowsHoverWithoutExit
        nsView.updateTrackingAreas()
    }

    func allowsHoverAfterExit(_ enabled: Bool) -> HoverTrackingView {
        var copy = self
        copy.allowsHoverWithoutExit = enabled
        return copy
    }
}

private final class MouseTrackingNSView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    var allowsHoverWithoutExit = true {
        didSet {
            guard oldValue != allowsHoverWithoutExit else { return }
            suppressHoverUntilExit = !allowsHoverWithoutExit
            if suppressHoverUntilExit {
                setHovering(false)
            } else {
                reconcileHoverState()
            }
        }
    }
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var hoverMonitorTimer: Timer?
    private var suppressHoverUntilExit = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        suppressHoverUntilExit = !allowsHoverWithoutExit
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
        reconcileHoverState()
    }

    override func mouseEntered(with event: NSEvent) {
        guard !suppressHoverUntilExit else { return }
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        if suppressHoverUntilExit {
            suppressHoverUntilExit = false
        }
        setHovering(false)
    }

    override func mouseMoved(with event: NSEvent) {
        reconcileHoverState()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        reconcileHoverState()
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
        let isInsideBounds = hoverBounds.contains(location)

        if suppressHoverUntilExit {
            if !isInsideBounds {
                suppressHoverUntilExit = false
            }
            setHovering(false)
            return
        }

        setHovering(isInsideBounds)
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
        IslandShellStyle.forState(
            state,
            approvalPanelShowsDenyReason: controller.approvalPanelShowsDenyReason
        ).size
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

    private var collapsedSessionCountFont: Font {
        let pixelCandidates = [
            "Silkscreen-Regular",
            "PressStart2P-Regular",
            "PixeloidSans",
            "PixeloidMono",
            "Monaco",
        ]

        for name in pixelCandidates {
            if let font = NSFont(name: name, size: 11) {
                return Font(font)
            }
        }

        return .system(size: 11, weight: .bold, design: .monospaced)
    }

    var body: some View {
        ZStack(alignment: .top) {
            collapsedContent
            expandedContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .mask {
            AnimatedNotchShape(
                shellWidth: IslandShellStyle.forState(
                    state,
                    approvalPanelShowsDenyReason: controller.approvalPanelShowsDenyReason
                ).size.width,
                shellHeight: IslandShellStyle.forState(
                    state,
                    approvalPanelShowsDenyReason: controller.approvalPanelShowsDenyReason
                ).size.height,
                topRadius: IslandShellStyle.forState(
                    state,
                    approvalPanelShowsDenyReason: controller.approvalPanelShowsDenyReason
                ).topRadius,
                bottomRadius: IslandShellStyle.forState(
                    state,
                    approvalPanelShowsDenyReason: controller.approvalPanelShowsDenyReason
                ).bottomRadius
            )
        }
    }

    private var collapsedContent: some View {
        ZStack {
            AnimatedSpriteIcon(color: collapsedActivityColor)
                .frame(width: 24)
                .offset(x: -102)

            Text(collapsedRunningSessionCountText)
                .font(collapsedSessionCountFont)
                .kerning(0.4)
                .foregroundStyle(collapsedActivityColor)
                .offset(x: 102)
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

    private var isSuspiciousSessionPanelActive: Bool {
        controller.activePanel == .sessionSuspicious
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
                ZStack(alignment: .leading) {
                    Text(expandedTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .id(expandedTitle)
                        .transition(.gaussianBlurText)
                }
                .animation(.easeInOut(duration: 0.2), value: expandedTitle)

                ZStack(alignment: .leading) {
                    if let subtitle = expandedSubtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .id("subtitle-\(subtitle)")
                            .transition(.gaussianBlurText)
                    } else if !isSettingsPanelActive {
                        Text(l10n.trackedSessions(sessionController.sessions.count))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .id("tracked-\(sessionController.sessions.count)")
                            .transition(.gaussianBlurText)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: expandedSubtitleTransitionKey)
            }

            Spacer()

            if !isApprovalPanelActive && !isSessionEndedPanelActive && !isSuspiciousSessionPanelActive {
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
        if isSuspiciousSessionPanelActive {
            return l10n.text("Suspicious Session", chinese: "可疑 Session")
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
            if isSuspiciousSessionPanelActive {
                return l10n.text("This session stopped receiving new events", chinese: "这个 session 在一段时间内没有收到新事件")
            }
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
        ZStack {
            if controller.activePanel == .settings {
                SettingsPanelView()
                    .environmentObject(settingsStore)
                    .id("settings")
                    .transition(.gaussianBlurPanel)
            } else if controller.activePanel == .sessionSuspicious {
                SuspiciousSessionPanelView()
                    .environmentObject(sessionController)
                    .environmentObject(settingsStore)
                    .id("sessionSuspicious")
                    .transition(.gaussianBlurPanel)
            } else if controller.activePanel == .sessionEnded {
                SessionEndedPanelView()
                    .environmentObject(sessionController)
                    .environmentObject(settingsStore)
                    .id("sessionEnded")
                    .transition(.gaussianBlurPanel)
            } else if let status = approvalPanelStatus {
                ApprovalPanelView(status: status, controller: controller)
                    .environmentObject(sessionController)
                    .environmentObject(settingsStore)
                    .id("approval-\(status == .pending ? "pending" : "completed")")
                    .transition(.gaussianBlurPanel)
            } else {
                CodexSessionListView()
                    .id("sessions")
                    .transition(.gaussianBlurPanel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: controller.activePanel)
    }

    private var expandedSubtitleTransitionKey: String {
        if let subtitle = expandedSubtitle {
            return "subtitle-\(subtitle)"
        }
        if !isSettingsPanelActive {
            return "tracked-\(sessionController.sessions.count)"
        }
        return "none"
    }
}

private struct AnimatedSpriteIcon: View {
    let color: Color

    private let frameSize = CGSize(width: 24, height: 16)
    private let frameCount = 26
    private let frameDuration = 1.0 / 12.0
    private let displayScale: CGFloat = 1.0

    var body: some View {
        TimelineView(.animation(minimumInterval: frameDuration, paused: false)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let frameIndex = Int(elapsed / frameDuration) % frameCount
            let spriteSheetWidth = frameSize.width * CGFloat(frameCount)

            Rectangle()
                .fill(color)
                .frame(width: frameSize.width, height: frameSize.height)
                .mask {
                    Image("cat")
                        .resizable()
                        .interpolation(.none)
                        .frame(width: spriteSheetWidth, height: frameSize.height, alignment: .leading)
                        .offset(x: -CGFloat(frameIndex) * frameSize.width)
                        .frame(width: frameSize.width, height: frameSize.height, alignment: .leading)
                        .clipped()
                        .luminanceToAlpha()
                }
                .scaleEffect(displayScale, anchor: .center)
        }
    }
}

private struct SuspiciousSessionPanelView: View {
    @EnvironmentObject private var sessionController: CodexSessionController
    @EnvironmentObject private var settingsStore: SettingsConfigStore

    private var l10n: AppLocalization {
        AppLocalization(language: settingsStore.config.appLanguage)
    }

    var body: some View {
        let notification = sessionController.suspiciousSessionNotification
        let timeout = settingsStore.config.suspiciousSessionTimeout

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 42, height: 42)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(notification?.title ?? l10n.text("Suspicious Session", chinese: "可疑 Session"))
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
                "No new event was received before the inactivity timeout. The session is still open but has been marked suspicious.",
                chinese: "在不活跃超时之前没有收到新的事件。这个 session 还没有结束，但已经被标记为可疑。"
            ))
            .font(.caption)
            .foregroundStyle(.white.opacity(0.72))
            .fixedSize(horizontal: false, vertical: true)

            Text(l10n.text("Timeout: \(timeout)s", chinese: "超时时间：\(timeout) 秒"))
                .font(.caption2)
                .foregroundStyle(.orange.opacity(0.9))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    @ObservedObject var controller: IslandController
    @EnvironmentObject private var sessionController: CodexSessionController
    @EnvironmentObject private var settingsStore: SettingsConfigStore
    @State private var isEnteringDenyReason = false
    @State private var denyReason = ""

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
                    .id(controller.approvalCompletionAnimationToken)
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

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ApprovalCapsuleButton(
                        title: l10n.text("Approve", chinese: "批准"),
                        fill: Color.green.opacity(0.9),
                        stroke: Color.green.opacity(0.55)
                    ) {
                        controller.updateApprovalPanelLayout(showsDenyReason: false)
                        isEnteringDenyReason = false
                        denyReason = ""
                        sessionController.approve(toolCall)
                    }

                    ApprovalCapsuleButton(
                        title: l10n.text("Deny", chinese: "拒绝"),
                        fill: Color.red.opacity(0.9),
                        stroke: Color.red.opacity(0.55)
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isEnteringDenyReason.toggle()
                            if !isEnteringDenyReason {
                                denyReason = ""
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                if isEnteringDenyReason {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(l10n.text("Block reason", chinese: "拦截原因"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        TextField(
                            l10n.text("Tell Codex why this tool was blocked", chinese: "告诉 Codex 为什么拦截这个工具"),
                            text: $denyReason,
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)

                        HStack(spacing: 8) {
                            ApprovalCapsuleButton(
                                title: l10n.text("Confirm Block", chinese: "确认拦截"),
                                fill: Color.red.opacity(0.9),
                                stroke: Color.red.opacity(0.55)
                            ) {
                                controller.updateApprovalPanelLayout(showsDenyReason: false)
                                sessionController.deny(toolCall, reason: denyReason)
                                isEnteringDenyReason = false
                                denyReason = ""
                            }

                            ApprovalCapsuleButton(
                                title: l10n.text("Cancel", chinese: "取消"),
                                fill: Color.white.opacity(0.08),
                                stroke: Color.white.opacity(0.12)
                            ) {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    isEnteringDenyReason = false
                                    denyReason = ""
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.top, 2)
            .onChange(of: isEnteringDenyReason) { newValue in
                controller.updateApprovalPanelLayout(showsDenyReason: newValue)
            }
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

private struct ToolApprovalActionBar: View {
    let approveTitle: String
    let denyTitle: String
    let denyReasonTitle: String
    let denyReasonPlaceholder: String
    let confirmDenyTitle: String
    let onApprove: () -> Void
    let onDeny: (String) -> Void

    @State private var isEnteringDenyReason = false
    @State private var denyReason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ApprovalCapsuleButton(
                    title: approveTitle,
                    fill: Color.green.opacity(0.9),
                    stroke: Color.green.opacity(0.55)
                ) {
                    onApprove()
                }

                ApprovalCapsuleButton(
                    title: denyTitle,
                    fill: Color.red.opacity(0.9),
                    stroke: Color.red.opacity(0.55)
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isEnteringDenyReason.toggle()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if isEnteringDenyReason {
                VStack(alignment: .leading, spacing: 8) {
                    Text(denyReasonTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    TextField(denyReasonPlaceholder, text: $denyReason, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)

                    HStack(spacing: 8) {
                        ApprovalCapsuleButton(
                            title: confirmDenyTitle,
                            fill: Color.red.opacity(0.9),
                            stroke: Color.red.opacity(0.55)
                        ) {
                            onDeny(denyReason)
                        }

                        ApprovalCapsuleButton(
                            title: "Cancel",
                            fill: Color.white.opacity(0.08),
                            stroke: Color.white.opacity(0.12)
                        ) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isEnteringDenyReason = false
                                denyReason = ""
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct ApprovalCapsuleButton: View {
    let title: String
    let fill: Color
    let stroke: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(ApprovalCapsuleButtonStyle(fill: fill, stroke: stroke))
    }
}

private struct ApprovalCapsuleButtonStyle: ButtonStyle {
    let fill: Color
    let stroke: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
                                ToolApprovalActionBar(
                                    approveTitle: l10n.text("Approve", chinese: "批准"),
                                    denyTitle: l10n.text("Deny", chinese: "拒绝"),
                                    denyReasonTitle: l10n.text("Block reason", chinese: "拦截原因"),
                                    denyReasonPlaceholder: l10n.text("Tell Codex why this tool was blocked", chinese: "告诉 Codex 为什么拦截这个工具"),
                                    confirmDenyTitle: l10n.text("Confirm Block", chinese: "确认拦截"),
                                    onApprove: {
                                        sessionController.approve(toolCall)
                                    },
                                    onDeny: { reason in
                                        sessionController.deny(toolCall, reason: reason)
                                    }
                                )
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

            if let lastUserPrompt = session.lastUserPrompt, !lastUserPrompt.isEmpty {
                sessionDetailBox(label: "prompt", text: lastUserPrompt)
            }

            sessionDetailBox(
                label: "reply",
                text: {
                    if let lastAssistantMessage = session.lastAssistantMessage, !lastAssistantMessage.isEmpty {
                        return lastAssistantMessage
                    }
                    return "..."
                }()
            )

            sessionDetailBox(
                label: "time",
                text: session.updatedAt.formatted(date: .abbreviated, time: .shortened)
            )
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

    private func sessionDetailBox(label: String, text: String) -> some View {
        let rowHeight: CGFloat = 24

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: toolCallCornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.14))

            HStack(spacing: 0) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .frame(height: rowHeight)
                    .background(Color.secondary.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: toolCallCornerRadius, style: .continuous))

                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
    }

    private func stateColor(for state: CodexSessionState) -> Color {
        switch state {
        case .running:
            return .green
        case .suspicious:
            return .orange
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

struct GaussianBlurTransition: ViewModifier {
    let opacity: Double
    let blurRadius: CGFloat
    let offsetY: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: blurRadius)
            .scaleEffect(scale, anchor: .center)
            .offset(y: offsetY)
    }
}

extension AnyTransition {
    static var gaussianBlurText: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: GaussianBlurTransition(opacity: 0, blurRadius: 14, offsetY: 6, scale: 0.985),
                identity: GaussianBlurTransition(opacity: 1, blurRadius: 0, offsetY: 0, scale: 1)
            ),
            removal: .modifier(
                active: GaussianBlurTransition(opacity: 0, blurRadius: 14, offsetY: -6, scale: 1.015),
                identity: GaussianBlurTransition(opacity: 1, blurRadius: 0, offsetY: 0, scale: 1)
            )
        )
    }

    static var gaussianBlurPanel: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: GaussianBlurTransition(opacity: 0, blurRadius: 18, offsetY: 10, scale: 0.985),
                identity: GaussianBlurTransition(opacity: 1, blurRadius: 0, offsetY: 0, scale: 1)
            ),
            removal: .modifier(
                active: GaussianBlurTransition(opacity: 0, blurRadius: 18, offsetY: -10, scale: 1.015),
                identity: GaussianBlurTransition(opacity: 1, blurRadius: 0, offsetY: 0, scale: 1)
            )
        )
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
