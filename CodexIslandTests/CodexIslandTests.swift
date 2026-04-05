//
//  CodexIslandTests.swift
//  CodexIslandTests
//
//  Created by n3ur0 on 4/4/26.
//

import Foundation
import Testing
@testable import CodexIsland

struct CodexIslandTests {

    @MainActor
    @Test func sessionListUsesThreadNameAsTitle() async throws {
        let indexURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("session_index.jsonl")
        try FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {"id":"session-1","thread_name":"Review sessions UI"}
        """.write(to: indexURL, atomically: true, encoding: .utf8)

        let controller = CodexSessionController(
            threadNameStore: CodexSessionThreadNameStore(indexURL: indexURL)
        )

        let payload = """
        {
          "session_id": "session-1",
          "transcript_path": "/tmp/transcript.jsonl",
          "cwd": "/tmp/CodexIsland",
          "hook_event_name": "UserPromptSubmit",
          "model": "gpt-5.4",
          "permission_mode": "default",
          "turn_id": "turn-1",
          "prompt": "查看 codex sessions 列表标题"
        }
        """.data(using: .utf8)!

        _ = controller.handleIncomingPayload(payload, client: -1)

        #expect(controller.sessions.count == 1)
        #expect(controller.sessions[0].title == "Review sessions UI")
        #expect(controller.sessions[0].projectName == "CodexIsland")
    }

}
