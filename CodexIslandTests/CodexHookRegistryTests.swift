import Foundation
import Testing
@testable import CodexIsland

struct CodexHookRegistryTests {

    @Test func decodesSessionStartAndReturnsAdditionalContext() throws {
        let input = """
        {
          "session_id": "session-1",
          "transcript_path": "/tmp/transcript.jsonl",
          "cwd": "/tmp/workspace",
          "hook_event_name": "SessionStart",
          "model": "gpt-5.4",
          "permission_mode": "default",
          "source": "startup"
        }
        """.data(using: .utf8)!

        let registry = CodexHookRegistry(sessionStore: nil)
            .onSessionStart { context in
                #expect(context.source == .startup)
                return .sessionStart(additionalContext: "Load workspace rules first.")
            }

        let response = try registry.handle(input: input)

        #expect(response?.hookSpecificOutput?.hookEventName == .sessionStart)
        #expect(response?.hookSpecificOutput?.additionalContext == "Load workspace rules first.")
    }

    @Test func preToolUseCanDenyBashCommand() throws {
        let input = """
        {
          "session_id": "session-1",
          "transcript_path": null,
          "cwd": "/tmp/workspace",
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

        let registry = CodexHookRegistry(sessionStore: nil)
            .onPreToolUse { context in
                #expect(context.toolInput.command == "rm -rf build")
                return .denyToolUse(reason: "Destructive commands require manual review.")
            }

        let response = try registry.handle(input: input)

        #expect(response?.decision == .block)
        #expect(response?.hookSpecificOutput?.permissionDecision == .deny)
        #expect(response?.reason == "Destructive commands require manual review.")
    }

    @Test func postToolUseCanAttachFeedback() throws {
        let input = """
        {
          "session_id": "session-1",
          "transcript_path": null,
          "cwd": "/tmp/workspace",
          "hook_event_name": "PostToolUse",
          "model": "gpt-5.4",
          "permission_mode": "default",
          "turn_id": "turn-1",
          "tool_name": "Bash",
          "tool_use_id": "tool-1",
          "tool_input": {
            "command": "swift test"
          },
          "tool_response": {
            "exit_code": 1,
            "stderr": "1 test failed"
          }
        }
        """.data(using: .utf8)!

        let registry = CodexHookRegistry(sessionStore: nil)
            .onPostToolUse { context in
                #expect(context.toolInput.command == "swift test")
                #expect(context.toolName == .bash)
                return .postToolUseFeedback(
                    reason: "Tests failed.",
                    additionalContext: "Inspect the failing case before continuing."
                )
            }

        let response = try registry.handle(input: input)

        #expect(response?.decision == .block)
        #expect(response?.reason == "Tests failed.")
        #expect(response?.hookSpecificOutput?.hookEventName == .postToolUse)
        #expect(response?.hookSpecificOutput?.additionalContext == "Inspect the failing case before continuing.")
    }

    @Test func sessionEndUsesStopHookPayload() throws {
        let input = """
        {
          "session_id": "session-1",
          "transcript_path": "/tmp/transcript.jsonl",
          "cwd": "/tmp/workspace",
          "hook_event_name": "Stop",
          "model": "gpt-5.4",
          "permission_mode": "default",
          "turn_id": "turn-1",
          "stop_hook_active": false,
          "last_assistant_message": "All tests passed."
        }
        """.data(using: .utf8)!

        let registry = CodexHookRegistry(sessionStore: nil)
            .onSessionEnd { context in
                #expect(context.lastAssistantMessage == "All tests passed.")
                return .sessionEndContinue(reason: "Run one more lint pass.")
            }

        let response = try registry.handle(input: input)
        let encoded = try registry.encodedResponse(for: input)
        let encodedString = encoded.flatMap { String(data: $0, encoding: .utf8) }

        #expect(response?.decision == .block)
        #expect(response?.reason == "Run one more lint pass.")
        #expect(encodedString?.contains("\"decision\":\"block\"") == true)
    }

    @Test func recentSessionsLoadTitlesAndStates() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("hook-sessions.json")
        let formatter = ISO8601DateFormatter()

        let runningRegistry = CodexHookRegistry(
            sessionStore: CodexSessionStore(
                storeURL: storeURL,
                now: formatter.date(from: "2026-04-04T12:24:01Z")!
            )
        )
        let completedRegistry = CodexHookRegistry(
            sessionStore: CodexSessionStore(
                storeURL: storeURL,
                now: formatter.date(from: "2026-04-04T12:28:07Z")!
            )
        )

        let sessionStart = """
        {
          "session_id": "session-running",
          "transcript_path": "/tmp/running.jsonl",
          "cwd": "/tmp/Active Session",
          "hook_event_name": "SessionStart",
          "model": "gpt-5.4",
          "permission_mode": "default",
          "source": "startup"
        }
        """.data(using: .utf8)!

        let stop = """
        {
          "session_id": "session-idle",
          "transcript_path": "/tmp/idle.jsonl",
          "cwd": "/tmp/Idle Session",
          "hook_event_name": "Stop",
          "model": "gpt-5.4",
          "permission_mode": "default",
          "turn_id": "turn-1",
          "stop_hook_active": false,
          "last_assistant_message": "Finished."
        }
        """.data(using: .utf8)!

        _ = try runningRegistry.handle(input: sessionStart)
        _ = try completedRegistry.handle(input: stop)

        let sessions = try CodexSessionStore(storeURL: storeURL).recentSessions(limit: 2)

        #expect(sessions.count == 2)
        #expect(sessions[0].title == "Idle Session")
        #expect(sessions[0].state == .completed)
        #expect(sessions[1].title == "Active Session")
        #expect(sessions[1].state == .running)
    }

    @Test func userPromptSubmitCanBeBlockedAndPersisted() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("hook-sessions.json")

        let input = """
        {
          "session_id": "session-1",
          "transcript_path": "/tmp/transcript.jsonl",
          "cwd": "/tmp/workspace",
          "hook_event_name": "UserPromptSubmit",
          "model": "gpt-5.4",
          "permission_mode": "plan",
          "turn_id": "turn-1",
          "prompt": "Refactor the helper/app bridge."
        }
        """.data(using: .utf8)!

        let registry = CodexHookRegistry(
            sessionStore: CodexSessionStore(storeURL: storeURL)
        )
            .onUserPromptSubmit { context in
                #expect(context.prompt == "Refactor the helper/app bridge.")
                return .blockUserPrompt(
                    reason: "Need a smaller scope first.",
                    additionalContext: "Split transport and UI."
                )
            }

        let response = try registry.handle(input: input)
        let sessions = try CodexSessionStore(storeURL: storeURL).recentSessions(limit: 1)

        #expect(response?.decision == .block)
        #expect(response?.reason == "Need a smaller scope first.")
        #expect(response?.hookSpecificOutput?.hookEventName == .userPromptSubmit)
        #expect(sessions.first?.lastUserPrompt == "Refactor the helper/app bridge.")
    }
}
