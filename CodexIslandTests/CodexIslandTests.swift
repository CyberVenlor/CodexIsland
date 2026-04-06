//
//  CodexIslandTests.swift
//  CodexIslandTests
//
//  Created by n3ur0 on 4/4/26.
//

import Foundation
import SQLite3
import Testing
@testable import CodexIsland

struct CodexIslandTests {

    @MainActor
    @Test func collapsedIslandEntersApprovalPanelWhenUnsafeToolIsPending() async throws {
        let islandController = IslandController()

        islandController.updateApprovalPresentation(hasPendingApproval: true)

        #expect(islandController.isExpanded == true)
        #expect(islandController.activePanel == .approval(status: .pending))
    }

    @MainActor
    @Test func expandedIslandDoesNotAutoSwitchIntoApprovalPanel() async throws {
        let islandController = IslandController()

        islandController.expand()
        islandController.updateApprovalPresentation(hasPendingApproval: true)

        #expect(islandController.isExpanded == true)
        #expect(islandController.activePanel == .sessions)
    }

    @MainActor
    @Test func approvalPanelCompletesThenReturnsToCollapsedState() async throws {
        let islandController = IslandController()

        islandController.updateApprovalPresentation(hasPendingApproval: true)
        islandController.updateApprovalPresentation(hasPendingApproval: false)

        #expect(islandController.activePanel == .approval(status: .completed))

        try await Task.sleep(for: .milliseconds(950))

        #expect(islandController.isExpanded == false)
        #expect(islandController.activePanel == .sessions)
    }

    @MainActor
    @Test func sessionListUsesThreadNameAsTitle() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directoryURL.appendingPathComponent("state_5.sqlite")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let database = try SQLiteDatabase(url: databaseURL)
        try database.execute("""
        CREATE TABLE threads (
            id TEXT PRIMARY KEY,
            rollout_path TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            source TEXT NOT NULL,
            model_provider TEXT NOT NULL,
            cwd TEXT NOT NULL,
            title TEXT NOT NULL,
            sandbox_policy TEXT NOT NULL,
            approval_mode TEXT NOT NULL,
            tokens_used INTEGER NOT NULL DEFAULT 0,
            has_user_event INTEGER NOT NULL DEFAULT 0,
            archived INTEGER NOT NULL DEFAULT 0
        );
        """)
        try database.execute("""
        INSERT INTO threads (
            id, rollout_path, created_at, updated_at, source, model_provider, cwd, title, sandbox_policy, approval_mode
        ) VALUES (
            'session-1', '/tmp/rollout.jsonl', 0, 0, 'desktop', 'openai', '/tmp/CodexIsland', 'Review sessions UI', 'workspace-write', 'default'
        );
        """)

        let controller = CodexSessionController(
            threadNameStore: CodexSessionThreadNameStore(databaseURL: databaseURL)
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

    @MainActor
    @Test func sessionListFallsBackToProjectNameWhenThreadNameMissing() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directoryURL.appendingPathComponent("state_5.sqlite")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let controller = CodexSessionController(
            threadNameStore: CodexSessionThreadNameStore(databaseURL: databaseURL)
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
          "prompt": "这不应该作为标题"
        }
        """.data(using: .utf8)!

        _ = controller.handleIncomingPayload(payload, client: -1)

        #expect(controller.sessions.count == 1)
        #expect(controller.sessions[0].title == "CodexIsland")
    }

    @MainActor
    @Test func timedOutApprovalStopsPinningToolCardAsPending() async throws {
        let controller = CodexSessionController(
            threadNameStore: CodexSessionThreadNameStore(
                databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                indexURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
        )

        let pendingPayload = """
        {
          "session_id": "session-1",
          "transcript_path": "/tmp/transcript.jsonl",
          "cwd": "/tmp/CodexIsland",
          "hook_event_name": "PreToolUse",
          "model": "gpt-5.4",
          "permission_mode": "default",
          "turn_id": "turn-1",
          "tool_name": "Bash",
          "tool_use_id": "tool-1",
          "tool_input": {
            "command": "swift test"
          }
        }
        """.data(using: .utf8)!

        _ = controller.handleIncomingPayload(pendingPayload, client: -1)

        #expect(controller.sessions.first?.toolCalls.first?.requiresApproval == true)
        #expect(controller.sessions.first?.toolCalls.first?.approvalStatus == "pending")

        let timedOutPayload = """
        {
          "session_id": "session-1",
          "cwd": "/tmp/CodexIsland",
          "model": "gpt-5.4",
          "tool_use_id": "tool-1",
          "tool_name": "Bash",
          "tool_input": {
            "command": "swift test"
          },
          "codex_event_type": "hook-post-tool-use",
          "permission_status": "timed_out"
        }
        """.data(using: .utf8)!

        _ = controller.handleIncomingPayload(timedOutPayload, client: -1)

        #expect(controller.sessions.first?.toolCalls.isEmpty == true)
    }

    @MainActor
    @Test func safePreToolUseCommandDoesNotEnterApprovalQueue() async throws {
        let controller = CodexSessionController(
            threadNameStore: CodexSessionThreadNameStore(
                databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                indexURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
        )

        let payload = """
        {
          "session_id": "session-1",
          "transcript_path": "/tmp/transcript.jsonl",
          "cwd": "/tmp/CodexIsland",
          "hook_event_name": "PreToolUse",
          "model": "gpt-5.4",
          "permission_mode": "default",
          "turn_id": "turn-1",
          "tool_name": "Bash",
          "tool_use_id": "tool-1",
          "tool_input": {
            "command": "git status"
          }
        }
        """.data(using: .utf8)!

        let disposition = controller.handleIncomingPayload(payload, client: -1)

        #expect(disposition == .closeClient)
        #expect(controller.sessions.first?.toolCalls.isEmpty == true)
    }

    @MainActor
    @Test func quotedPipeInReadOnlyCommandDoesNotRequireApproval() async throws {
        let controller = CodexSessionController(
            threadNameStore: CodexSessionThreadNameStore(
                databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                indexURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
        )

        let payload = """
        {
          "session_id": "session-1",
          "transcript_path": "/tmp/transcript.jsonl",
          "cwd": "/tmp/CodexIsland",
          "hook_event_name": "PreToolUse",
          "model": "gpt-5.4",
          "permission_mode": "default",
          "turn_id": "turn-1",
          "tool_name": "Bash",
          "tool_use_id": "tool-1",
          "tool_input": {
            "command": "rg \\"foo|bar\\" Sources"
          }
        }
        """.data(using: .utf8)!

        let disposition = controller.handleIncomingPayload(payload, client: -1)

        #expect(disposition == .closeClient)
        #expect(controller.sessions.first?.toolCalls.isEmpty == true)
    }

    @MainActor
    @Test func destructivePreToolUseCommandStillRequiresApproval() async throws {
        let controller = CodexSessionController(
            threadNameStore: CodexSessionThreadNameStore(
                databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                indexURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
        )

        let payload = """
        {
          "session_id": "session-1",
          "transcript_path": "/tmp/transcript.jsonl",
          "cwd": "/tmp/CodexIsland",
          "hook_event_name": "PreToolUse",
          "model": "gpt-5.4",
          "permission_mode": "default",
          "turn_id": "turn-1",
          "tool_name": "Bash",
          "tool_use_id": "tool-1",
          "tool_input": {
            "command": "rm -rf build"
          }
        }
        """.data(using: .utf8)!

        let disposition = controller.handleIncomingPayload(payload, client: -1)

        #expect(disposition == .holdClient)
        #expect(controller.sessions.first?.toolCalls.first?.requiresApproval == true)
        #expect(controller.sessions.first?.toolCalls.first?.approvalStatus == "pending")
    }

}

private final class SQLiteDatabase {
    let handle: OpaquePointer

    init(url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw SQLiteError.openFailed
        }

        handle = database
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteError.executionFailed
        }
    }

    deinit {
        sqlite3_close(handle)
    }
}

private enum SQLiteError: Error {
    case openFailed
    case executionFailed
}
