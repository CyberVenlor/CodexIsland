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
          "source": "startup"
        }
        """.data(using: .utf8)!

        let registry = CodexHookRegistry()
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
          "turn_id": "turn-1",
          "tool_name": "Bash",
          "tool_use_id": "tool-1",
          "tool_input": {
            "command": "rm -rf build"
          }
        }
        """.data(using: .utf8)!

        let registry = CodexHookRegistry()
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

        let registry = CodexHookRegistry()
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
          "turn_id": "turn-1",
          "stop_hook_active": false,
          "last_assistant_message": "All tests passed."
        }
        """.data(using: .utf8)!

        let registry = CodexHookRegistry()
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
}
