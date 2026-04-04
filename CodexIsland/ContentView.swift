//
//  ContentView.swift
//  CodexIsland
//
//  Created by n3ur0 on 4/4/26.
//

import SwiftUI

struct ContentView: View {
    @State private var sessions: [CodexRecentSession] = []

    var body: some View {
        NavigationStack {
            List(sessions) { session in
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

                    Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Recent Codex Sessions",
                        systemImage: "bolt.slash",
                        description: Text("No sessions were found in ~/.codex/session_index.jsonl.")
                    )
                }
            }
            .navigationTitle("Recent Codex Sessions")
        }
        .task {
            sessions = (try? CodexSessionStore().recentSessions(limit: 12)) ?? []
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
    }
}
