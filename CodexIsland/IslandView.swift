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
        .overlay(alignment: .top) {
            hoverHitArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var hoverHitArea: some View {
        Color.clear
            .frame(width: shellStyle.size.width, height: shellStyle.size.height)
            .contentShape(Rectangle())
            .onHover { isHovering in
                controller.handleHoverChange(isHovering)
            }
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
            sessionController: sessionController
        )
    }
}

struct IslandContentView: View {
    let state: IslandPresentationState
    @ObservedObject var sessionController: CodexSessionController

    private let detailedSize = IslandShellStyle.forState(.collapsed(.detailed)).size
    private let expandedSize = IslandShellStyle.forState(.expanded).size

    private var isExpanded: Bool {
        if case .expanded = state {
            return true
        }
        return false
    }

    private var isDetailedCollapsed: Bool {
        if case .collapsed(.detailed) = state {
            return true
        }
        return false
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

            Text("W")
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
            expandedDetails
        }
        .padding(.horizontal, 18)
        .padding(.top, 32)
        .padding(.bottom, 18)
        .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
        .opacity(isExpanded ? 1 : 0)
        .blur(radius: isExpanded ? 0 : 18)
    }

    @ViewBuilder
    private var expandedDetails: some View {
        CodexHooksExpandedPanel(sessionController: sessionController)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct CodexHooksExpandedPanel: View {
    @ObservedObject var sessionController: CodexSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if sessionController.sessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(sessionController.sessions) { session in
                            SessionCard(session: session, sessionController: sessionController)
                        }
                    }
                    .padding(.bottom, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Hooks")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("\(sessionController.sessions.count) active session\(sessionController.sessions.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))
            }

            Spacer()

            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.78))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Codex sessions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Text("Sessions appear here after the helper relay receives hook events.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SessionCard: View {
    let session: CodexSessionGroup
    @ObservedObject var sessionController: CodexSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(session.projectName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                SessionStateBadge(state: session.state)
            }

            if let prompt = session.lastUserPrompt, !prompt.isEmpty {
                SessionExcerpt(label: "Prompt", text: prompt)
            }

            if let message = session.lastAssistantMessage, !message.isEmpty {
                SessionExcerpt(label: "Reply", text: message)
            }

            ForEach(session.toolCalls) { toolCall in
                ToolCallCard(toolCall: toolCall, sessionController: sessionController)
            }

            Text(session.updatedAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ToolCallCard: View {
    let toolCall: CodexToolCall
    @ObservedObject var sessionController: CodexSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(toolCall.toolName ?? toolCall.toolUseID ?? "Tool")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                if let approvalStatus = toolCall.approvalStatus {
                    Text(approvalStatus)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(toolCall.requiresApproval ? .black : .white.opacity(0.82))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            toolCall.requiresApproval ? Color.yellow : Color.white.opacity(0.12),
                            in: Capsule()
                        )
                }
            }

            if let command = toolCall.toolCommand {
                Text(command)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.72))
                    .textSelection(.enabled)
                    .lineLimit(3)
            }

            if toolCall.requiresApproval {
                HStack(spacing: 8) {
                    Button("Approve") {
                        sessionController.approve(toolCall)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.green)

                    Button("Deny") {
                        sessionController.deny(toolCall)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.white.opacity(0.8))
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SessionExcerpt: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.46))

            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(2)
        }
    }
}

private struct SessionStateBadge: View {
    let state: CodexSessionState

    var body: some View {
        Text(state.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
    }

    private var color: Color {
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
