//
//  ContentView.swift
//  CodexIsland
//
//  Created by n3ur0 on 4/4/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bridgeServer: CodexBridgeServer

    var body: some View {
        NavigationStack {
            List(bridgeServer.sessions) { session in
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
                if let loadError = bridgeServer.loadError {
                    ContentUnavailableView(
                        "Unable to Load Codex Sessions",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else if bridgeServer.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Recent Codex Sessions",
                        systemImage: "bolt.slash",
                        description: Text("No sessions were captured from Codex hooks yet.")
                    )
                }
            }
            .navigationTitle("Recent Codex Sessions")
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
            .environmentObject(CodexBridgeServer())
    }
}
