import Foundation

@_silgen_name("codex_command_requires_approval")
private func codex_command_requires_approval(
    _ toolName: UnsafePointer<CChar>,
    _ command: UnsafePointer<CChar>
) -> Int32

enum CodexCommandApprovalMatcher {
    static func requiresApproval(for context: CodexPreToolUseContext) -> Bool {
        requiresApproval(toolName: context.toolName, command: context.toolInput.command)
    }

    static func requiresApproval(toolName: CodexToolName, command: String) -> Bool {
        toolName.displayName.withCString { toolNamePointer in
            command.withCString { commandPointer in
                codex_command_requires_approval(toolNamePointer, commandPointer) != 0
            }
        }
    }
}
