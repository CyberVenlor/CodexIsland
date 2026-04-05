import AppKit
import SwiftUI

struct IslandView: View {
    @ObservedObject var controller: IslandController
    @EnvironmentObject private var sessionController: CodexSessionController
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

    var body: some View {
        ZStack {
            islandBody
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .top)
        .contextMenu {
            ForEach(CollapsedIslandMode.allCases) { mode in
                Button(mode.title) {
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
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 24)
                .offset(x: -100)

            Text(collapsedRunningSessionCountText)
                .foregroundStyle(.white)
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

    private var expandedHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.activePanel == .settings ? "Settings" : "Codex Sessions")
                    .font(.headline)
                    .foregroundStyle(.white)

                if controller.activePanel == .settings {
                    Text("Panel is still in progress.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    Text("\(sessionController.sessions.count) tracked")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            Spacer()

            Button {
                controller.toggleSettingsPanel()
            } label: {
                Image(systemName: controller.activePanel == .settings ? "xmark.circle.fill" : "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .help(controller.activePanel == .settings ? "Close Settings" : "Open Settings")
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var expandedDetails: some View {
        if controller.activePanel == .settings {
            SettingsPanelView()
                .environmentObject(settingsStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            CodexSessionListView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct CodexSessionListView: View {
    @EnvironmentObject private var sessionController: CodexSessionController
    private let sessionCornerRadius: CGFloat = 16
    private let toolCallCornerRadius: CGFloat = 12
    private let sessionStackAnimation = Animation.spring(response: 0.42, dampingFraction: 0.86)

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
                    "No Codex Sessions",
                    systemImage: "bolt.slash",
                    description: Text("Only sessions received after this app launch are tracked.")
                )
            }
        }
        .animation(sessionStackAnimation, value: sessionController.sessions.map(\.id))
    }

    private func sessionRow(_ session: CodexSessionGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(2)

                Spacer()

                HStack(spacing: 8) {
                    Text(session.projectName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Text(session.state.displayName)
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
                            Text("tool: \(toolCall.toolName ?? toolCall.toolUseID ?? "-")")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let toolUseID = toolCall.toolUseID {
                                Text("toolUseId: \(toolUseID)")
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
                                    Button("Approve") {
                                        sessionController.approve(toolCall)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("Deny") {
                                        sessionController.deny(toolCall)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            } else if let approvalStatus = toolCall.approvalStatus {
                                Text("approval: \(approvalStatus)")
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
