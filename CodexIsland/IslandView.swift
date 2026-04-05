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
        .contentShape(Rectangle())
        .onHover { isHovering in
            controller.handleHoverChange(isHovering)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        CodexSessionListView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct CodexSessionListView: View {
    @EnvironmentObject private var sessionController: CodexSessionController
    private let sessionCornerRadius: CGFloat = 16
    private let toolCallCornerRadius: CGFloat = 12

    var body: some View {
        NavigationStack {
            List(sessionController.sessions) { session in
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
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
            .navigationTitle("Codex Sessions")
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
