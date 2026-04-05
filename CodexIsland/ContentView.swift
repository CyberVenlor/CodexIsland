//
//  ContentView.swift
//  CodexIsland
//
//  Created by n3ur0 on 4/4/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sessionController: CodexSessionController

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

                            Text(session.state.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(stateColor(for: session.state))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(stateColor(for: session.state).opacity(0.15), in: Capsule())
                        }
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
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    if let lastUserPrompt = session.lastUserPrompt, !lastUserPrompt.isEmpty {
                        Text(lastUserPrompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
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
                .padding(.vertical, 4)
            }
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(CodexSessionController())
    }
}
