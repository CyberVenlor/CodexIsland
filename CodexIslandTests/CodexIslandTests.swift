//
//  CodexIslandTests.swift
//  CodexIslandTests
//
//  Created by n3ur0 on 4/4/26.
//

import Foundation
import SQLite3
import Testing
import Darwin
@testable import CodexIsland

struct CodexIslandTests {

    @Test func appLanguageRecognizesChinesePreferenceVariants() {
        #expect(AppLanguage(preference: "Chinese") == .chinese)
        #expect(AppLanguage(preference: "中文") == .chinese)
        #expect(AppLanguage(preference: "zh-Hans") == .chinese)
        #expect(AppLanguage(preference: "English") == .english)
    }

    @Test func appLocalizationReturnsChineseLabels() {
        let localization = AppLocalization(language: .chinese)

        #expect(localization.text("Settings", chinese: "设置") == "设置")
        #expect(localization.trackedSessions(3) == "已跟踪 3 个")
        #expect(localization.localizedApprovalStatus("approved") == "已批准")
        #expect(localization.localizedSessionState(.running) == "运行中")
        #expect(localization.localizedSessionState(.suspicious) == "可疑")
    }

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
    @Test func sessionEndedPanelExpandsThenReturnsToCollapsedState() async throws {
        let islandController = IslandController()

        islandController.presentSessionEndedPanel()

        #expect(islandController.isExpanded == true)
        #expect(islandController.activePanel == .sessionEnded)

        try await Task.sleep(for: .milliseconds(2300))

        #expect(islandController.isExpanded == false)
        #expect(islandController.activePanel == .sessions)
    }

    @MainActor
    @Test func suspiciousSessionPanelExpandsThenReturnsToCollapsedState() async throws {
        let islandController = IslandController()

        islandController.presentSuspiciousSessionPanel()

        #expect(islandController.isExpanded == true)
        #expect(islandController.activePanel == .sessionSuspicious)

        try await Task.sleep(for: .milliseconds(2300))

        #expect(islandController.isExpanded == false)
        #expect(islandController.activePanel == .sessions)
    }

    @MainActor
    @Test func approvalDecisionCountsTrackApprovedAndDeniedTools() async throws {
        let controller = CodexSessionController(
            threadNameStore: CodexSessionThreadNameStore(
                databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                indexURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
        )

        let approvePair = try makeSocketPair()
        defer {
            close(approvePair.0)
            close(approvePair.1)
        }

        let denyPair = try makeSocketPair()
        defer {
            close(denyPair.0)
            close(denyPair.1)
        }

        _ = controller.handleIncomingPayload(
            preToolUsePayload(sessionID: "session-1", toolUseID: "tool-1", command: "rm -rf build"),
            client: approvePair.0
        )
        _ = controller.handleIncomingPayload(
            preToolUsePayload(sessionID: "session-1", toolUseID: "tool-2", command: "sudo rm -rf /tmp/foo"),
            client: denyPair.0
        )

        let firstTool = try #require(controller.pendingApprovalToolCall)
        controller.approve(firstTool)

        let secondTool = try #require(controller.pendingApprovalToolCall)
        controller.deny(secondTool)

        #expect(controller.approvalDecisionCounts.approved == 1)
        #expect(controller.approvalDecisionCounts.denied == 1)
        #expect(controller.pendingApprovalToolCall == nil)
    }

    @MainActor
    @Test func completedStopPublishesSessionEndedNotification() async throws {
        let controller = CodexSessionController(
            threadNameStore: CodexSessionThreadNameStore(
                databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                indexURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
        )

        controller.updateHookSettings(SettingsConfig())

        _ = controller.handleIncomingPayload(
            userPromptPayload(sessionID: "session-1"),
            client: -1
        )
        _ = controller.handleIncomingPayload(
            stopPayload(sessionID: "session-1", stopHookActive: false),
            client: -1
        )

        #expect(controller.sessionEndedNotification?.sessionID == "session-1")
    }

    @MainActor
    @Test func completedStopDoesNotPublishSessionEndedNotificationWhenDisabled() async throws {
        let controller = CodexSessionController(
            threadNameStore: CodexSessionThreadNameStore(
                databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                indexURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
        )

        var config = SettingsConfig()
        config.showSessionEndNotifications = false
        controller.updateHookSettings(config)

        _ = controller.handleIncomingPayload(
            userPromptPayload(sessionID: "session-1"),
            client: -1
        )
        _ = controller.handleIncomingPayload(
            stopPayload(sessionID: "session-1", stopHookActive: false),
            client: -1
        )

        #expect(controller.sessionEndedNotification == nil)
    }

    @MainActor
    @Test func inactiveSessionBecomesSuspiciousAndPublishesNotification() async throws {
        let controller = CodexSessionController(
            threadNameStore: CodexSessionThreadNameStore(
                databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                indexURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
        )

        var config = SettingsConfig()
        config.suspiciousSessionTimeout = 1
        controller.updateHookSettings(config)

        _ = controller.handleIncomingPayload(
            userPromptPayload(sessionID: "session-1"),
            client: -1
        )

        #expect(controller.sessions.first?.state == .running)

        try await Task.sleep(for: .milliseconds(1100))

        #expect(controller.sessions.first?.state == .suspicious)
        #expect(controller.suspiciousSessionNotification?.sessionID == "session-1")
    }

    @MainActor
    @Test func newEventRestoresSuspiciousSessionToRunning() async throws {
        let controller = CodexSessionController(
            threadNameStore: CodexSessionThreadNameStore(
                databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                indexURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
        )

        var config = SettingsConfig()
        config.suspiciousSessionTimeout = 1
        controller.updateHookSettings(config)

        _ = controller.handleIncomingPayload(
            userPromptPayload(sessionID: "session-1"),
            client: -1
        )
        try await Task.sleep(for: .milliseconds(1100))
        #expect(controller.sessions.first?.state == .suspicious)

        _ = controller.handleIncomingPayload(
            userPromptPayload(sessionID: "session-1"),
            client: -1
        )

        #expect(controller.sessions.first?.state == .running)
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
            'session-1', '/tmp/rollout.jsonl', 0, 0, 'vscode', 'openai', '/tmp/CodexIsland', 'Review sessions UI', 'workspace-write', 'default'
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
        #expect(controller.sessions[0].source == .vscode)
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
    @Test func openSessionDelegatesToNavigator() async throws {
        let navigator = SessionNavigatorSpy()
        let controller = CodexSessionController(sessionNavigator: navigator)
        let session = CodexSessionGroup(
            id: "session-1",
            title: "Review sessions UI",
            projectName: "CodexIsland",
            updatedAt: Date(),
            state: .running,
            source: .cli,
            rolloutPath: "/tmp/rollout.jsonl",
            cwd: "/tmp/CodexIsland",
            model: "gpt-5.4",
            transcriptPath: "/tmp/transcript.jsonl",
            lastEvent: "UserPromptSubmit",
            lastUserPrompt: "open it",
            lastAssistantMessage: nil,
            toolCalls: []
        )

        let didOpen = controller.openSession(session)

        #expect(didOpen == true)
        #expect(navigator.openedSessions == [session])
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
    @Test func pipedReadOnlyCommandsDoNotRequireApproval() async throws {
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
            "command": "rg foo Sources | head -n 5"
          }
        }
        """.data(using: .utf8)!

        let disposition = controller.handleIncomingPayload(payload, client: -1)

        #expect(disposition == .closeClient)
        #expect(controller.sessions.first?.toolCalls.isEmpty == true)
    }

    @MainActor
    @Test func ifBlockWithReadOnlyCommandsDoesNotRequireApproval() async throws {
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
            "command": "if rg foo Sources; then head -n 1 README.md; fi"
          }
        }
        """.data(using: .utf8)!

        let disposition = controller.handleIncomingPayload(payload, client: -1)

        #expect(disposition == .closeClient)
        #expect(controller.sessions.first?.toolCalls.isEmpty == true)
    }

    @MainActor
    @Test func envPrefixedReadOnlyCommandDoesNotRequireApproval() async throws {
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
            "command": "FOO=1 swift test"
          }
        }
        """.data(using: .utf8)!

        let disposition = controller.handleIncomingPayload(payload, client: -1)

        #expect(disposition == .closeClient)
        #expect(controller.sessions.first?.toolCalls.isEmpty == true)
    }

    @MainActor
    @Test func helpFlagCommandDoesNotRequireApproval() async throws {
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
            "command": "git checkout -h"
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

    @Test func hooksConfigStoreWritesExpectedHooksJson() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let hooksURL = directoryURL.appendingPathComponent("hooks.json")
        let store = CodexHooksConfigStore(
            hooksURL: hooksURL,
            helperCommand: "/tmp/codex_hook_helper.py"
        )

        var config = SettingsConfig()
        config.hooksEnabled = true
        config.enablePreToolUseHook = true
        config.enablePostToolUseHook = false
        config.preToolUseTimeout = 300

        try store.write(config: config)

        let data = try Data(contentsOf: hooksURL)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hooks = decoded?["hooks"] as? [String: Any]

        #expect(hooks?["PreToolUse"] != nil)
        #expect(hooks?["PostToolUse"] == nil)

        let preToolUse = hooks?["PreToolUse"] as? [[String: Any]]
        let matcher = preToolUse?.first
        let commands = matcher?["hooks"] as? [[String: Any]]
        let command = commands?.first

        #expect(command?["command"] as? String == "/tmp/codex_hook_helper.py")
        #expect(command?["timeout"] as? Int == 300)
    }

    @MainActor
    @Test func pendingApprovalAutoDeniesBeforeHookTimeout() async throws {
        let controller = CodexSessionController(
            threadNameStore: CodexSessionThreadNameStore(
                databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                indexURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            ),
            autoDenyLeadTime: 0.95
        )

        var config = SettingsConfig()
        config.preToolUseTimeout = 1
        controller.updateHookSettings(config)

        var sockets = [Int32](repeating: 0, count: 2)
        #expect(socketpair(AF_UNIX, Int32(SOCK_STREAM), 0, &sockets) == 0)
        let clientSocket = sockets[0]
        let peerSocket = sockets[1]
        defer {
            close(peerSocket)
        }

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
            "command": "swift test"
          }
        }
        """.data(using: .utf8)!

        let disposition = controller.handleIncomingPayload(payload, client: clientSocket)
        #expect(disposition == .holdClient)

        try await Task.sleep(for: .milliseconds(250))

        let responseData = try FileHandle(fileDescriptor: peerSocket, closeOnDealloc: false).readToEnd() ?? Data()
        let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        let hookResponse = response?["hookResponse"] as? [String: Any]

        #expect(response?["decision"] as? String == "deny")
        #expect(hookResponse?["reason"] as? String == "Timed out waiting for approval from CodexIsland")
        #expect(controller.pendingApprovalToolCall == nil)
        #expect(controller.sessions.first?.toolCalls.isEmpty == true)
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

private final class SessionNavigatorSpy: CodexSessionNavigating {
    private(set) var openedSessions: [CodexSessionGroup] = []

    func open(_ session: CodexSessionGroup) -> Bool {
        openedSessions.append(session)
        return true
    }
}

private func preToolUsePayload(sessionID: String, toolUseID: String, command: String) -> Data {
    """
    {
      "session_id": "\(sessionID)",
      "transcript_path": "/tmp/transcript.jsonl",
      "cwd": "/tmp/CodexIsland",
      "hook_event_name": "PreToolUse",
      "model": "gpt-5.4",
      "permission_mode": "default",
      "turn_id": "turn-1",
      "tool_name": "Bash",
      "tool_use_id": "\(toolUseID)",
      "tool_input": {
        "command": "\(command)"
      }
    }
    """.data(using: .utf8)!
}

private func userPromptPayload(sessionID: String) -> Data {
    """
    {
      "session_id": "\(sessionID)",
      "transcript_path": "/tmp/transcript.jsonl",
      "cwd": "/tmp/CodexIsland",
      "hook_event_name": "UserPromptSubmit",
      "model": "gpt-5.4",
      "permission_mode": "default",
      "turn_id": "turn-1",
      "prompt": "test"
    }
    """.data(using: .utf8)!
}

private func stopPayload(sessionID: String, stopHookActive: Bool) -> Data {
    """
    {
      "session_id": "\(sessionID)",
      "transcript_path": "/tmp/transcript.jsonl",
      "cwd": "/tmp/CodexIsland",
      "hook_event_name": "Stop",
      "model": "gpt-5.4",
      "stop_hook_active": \(stopHookActive ? "true" : "false"),
      "last_assistant_message": "done"
    }
    """.data(using: .utf8)!
}

private func makeSocketPair() throws -> (Int32, Int32) {
    var descriptors: [Int32] = [0, 0]
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
        throw POSIXError(.EIO)
    }

    return (descriptors[0], descriptors[1])
}
