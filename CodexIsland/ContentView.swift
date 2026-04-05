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

                        Spacer()

                        Text(session.state.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(stateColor(for: session.state))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(stateColor(for: session.state).opacity(0.15), in: Capsule())
                    }

                    Text(session.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Text(session.cwd)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 12) {
                        Text("event: \(session.lastEvent ?? "-")")
                        Text("model: \(session.model)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let toolName = session.toolName ?? session.toolUseID {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PreToolUse")
                                .font(.caption.weight(.semibold))
                            Text("tool: \(toolName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let toolUseID = session.toolUseID {
                                Text("toolUseId: \(toolUseID)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }

                            if let toolCommand = session.toolCommand {
                                Text(toolCommand)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }

                            if session.requiresApproval {
                                HStack {
                                    Button("Approve") {
                                        sessionController.approve(session)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("Deny") {
                                        sessionController.deny(session)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            } else if let approvalStatus = session.approvalStatus {
                                Text("approval: \(approvalStatus)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if let lastUserPrompt = session.lastUserPrompt, !lastUserPrompt.isEmpty {
                        Text(lastUserPrompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let transcriptPath = session.transcriptPath {
                        Text(transcriptPath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
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
