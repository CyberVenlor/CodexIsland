import Foundation

enum CodexSessionProjection {
    static func session(from data: Data, now: Date = Date()) -> CodexRecentSession? {
        if let invocation = try? CodexHookInvocation.decode(from: data) {
            return session(from: invocation, now: now)
        }

        if let payload = try? JSONDecoder().decode(IncomingBridgePayload.self, from: data) {
            return session(from: payload, now: now)
        }

        return nil
    }

    static func merge(existing: CodexRecentSession, update: CodexRecentSession) -> CodexRecentSession {
        CodexRecentSession(
            id: existing.id,
            sessionID: existing.sessionID,
            projectName: update.projectName,
            updatedAt: update.updatedAt,
            state: update.state,
            cwd: update.cwd,
            model: update.model == "unknown" ? existing.model : update.model,
            transcriptPath: update.transcriptPath ?? existing.transcriptPath,
            lastEvent: update.lastEvent,
            lastUserPrompt: update.lastUserPrompt ?? existing.lastUserPrompt,
            lastAssistantMessage: update.lastAssistantMessage ?? existing.lastAssistantMessage,
            toolName: update.toolName ?? existing.toolName,
            toolUseID: update.toolUseID ?? existing.toolUseID,
            toolCommand: update.toolCommand ?? existing.toolCommand,
            requiresApproval: update.requiresApproval,
            approvalStatus: update.approvalStatus ?? existing.approvalStatus
        )
    }

    static func approvalUpdated(_ session: CodexRecentSession, status: String, now: Date = Date()) -> CodexRecentSession {
        CodexRecentSession(
            id: session.id,
            sessionID: session.sessionID,
            projectName: session.projectName,
            updatedAt: now,
            state: session.state,
            cwd: session.cwd,
            model: session.model,
            transcriptPath: session.transcriptPath,
            lastEvent: session.lastEvent,
            lastUserPrompt: session.lastUserPrompt,
            lastAssistantMessage: session.lastAssistantMessage,
            toolName: session.toolName,
            toolUseID: session.toolUseID,
            toolCommand: session.toolCommand,
            requiresApproval: false,
            approvalStatus: status
        )
    }

    private static func session(from invocation: CodexHookInvocation, now: Date) -> CodexRecentSession {
        switch invocation {
        case .sessionStart(let context):
            return CodexRecentSession(
                id: context.sessionID,
                sessionID: context.sessionID,
                projectName: title(from: context.cwd),
                updatedAt: now,
                state: .running,
                cwd: context.cwd,
                model: context.model,
                transcriptPath: context.transcriptPath,
                lastEvent: context.hookEventName.rawValue,
                lastUserPrompt: nil,
                lastAssistantMessage: nil,
                toolName: nil,
                toolUseID: nil,
                toolCommand: nil,
                requiresApproval: false,
                approvalStatus: nil
            )
        case .preToolUse(let context):
            let requiresApproval = CodexCommandApprovalMatcher.requiresApproval(for: context)
            return CodexRecentSession(
                id: toolEventID(sessionID: context.sessionID, toolUseID: context.toolUseID),
                sessionID: context.sessionID,
                projectName: title(from: context.cwd),
                updatedAt: now,
                state: .running,
                cwd: context.cwd,
                model: context.model,
                transcriptPath: context.transcriptPath,
                lastEvent: context.hookEventName.rawValue,
                lastUserPrompt: nil,
                lastAssistantMessage: nil,
                toolName: context.toolName.displayName,
                toolUseID: context.toolUseID,
                toolCommand: context.toolInput.command,
                requiresApproval: requiresApproval,
                approvalStatus: requiresApproval ? "pending" : nil
            )
        case .postToolUse(let context):
            return CodexRecentSession(
                id: toolEventID(sessionID: context.sessionID, toolUseID: context.toolUseID),
                sessionID: context.sessionID,
                projectName: title(from: context.cwd),
                updatedAt: now,
                state: .running,
                cwd: context.cwd,
                model: context.model,
                transcriptPath: context.transcriptPath,
                lastEvent: context.hookEventName.rawValue,
                lastUserPrompt: nil,
                lastAssistantMessage: nil,
                toolName: context.toolName.displayName,
                toolUseID: context.toolUseID,
                toolCommand: context.toolInput.command,
                requiresApproval: false,
                approvalStatus: nil
            )
        case .userPromptSubmit(let context):
            return CodexRecentSession(
                id: context.sessionID,
                sessionID: context.sessionID,
                projectName: title(from: context.cwd),
                updatedAt: now,
                state: .running,
                cwd: context.cwd,
                model: context.model,
                transcriptPath: context.transcriptPath,
                lastEvent: context.hookEventName.rawValue,
                lastUserPrompt: context.prompt,
                lastAssistantMessage: nil,
                toolName: nil,
                toolUseID: nil,
                toolCommand: nil,
                requiresApproval: false,
                approvalStatus: nil
            )
        case .stop(let context):
            return CodexRecentSession(
                id: context.sessionID,
                sessionID: context.sessionID,
                projectName: title(from: context.cwd),
                updatedAt: now,
                state: context.stopHookActive ? .running : .completed,
                cwd: context.cwd,
                model: context.model,
                transcriptPath: context.transcriptPath,
                lastEvent: context.hookEventName.rawValue,
                lastUserPrompt: nil,
                lastAssistantMessage: context.lastAssistantMessage,
                toolName: nil,
                toolUseID: nil,
                toolCommand: nil,
                requiresApproval: false,
                approvalStatus: nil
            )
        }
    }

    private static func session(from payload: IncomingBridgePayload, now: Date) -> CodexRecentSession {
        let eventName = payload.event ?? payload.codexEventType
        return CodexRecentSession(
            id: eventID(
                sessionID: payload.sessionID ?? UUID().uuidString,
                toolUseID: payload.toolUseID,
                eventName: eventName
            ),
            sessionID: payload.sessionID ?? UUID().uuidString,
            projectName: title(from: payload.cwd ?? payload.transcriptPath ?? "unknown"),
            updatedAt: now,
            state: state(for: payload),
            cwd: payload.cwd ?? payload.transcriptPath ?? "unknown",
            model: payload.model ?? "unknown",
            transcriptPath: payload.transcriptPath,
            lastEvent: eventName,
            lastUserPrompt: payload.prompt,
            lastAssistantMessage: payload.lastAssistantMessage,
            toolName: payload.toolName,
            toolUseID: payload.toolUseID,
            toolCommand: payload.toolCommand ?? payload.toolInput?.command,
            requiresApproval: payload.requiresApproval,
            approvalStatus: payload.requiresApproval ? "pending" : payload.permissionStatus
        )
    }

    private static func state(for payload: IncomingBridgePayload) -> CodexSessionState {
        let eventName = (payload.event ?? payload.codexEventType ?? "").lowercased()
        if eventName == "stop" || eventName == "hook-stop" || eventName == "hook-session-stop" {
            return payload.stopHookActive == true ? .running : .completed
        }
        return .running
    }

    private static func title(from path: String) -> String {
        let component = URL(fileURLWithPath: path).lastPathComponent
        return component.isEmpty ? path : component
    }

    private static func toolEventID(sessionID: String, toolUseID: String) -> String {
        "\(sessionID)::\(toolUseID)"
    }

    private static func eventID(sessionID: String, toolUseID: String?, eventName: String?) -> String {
        guard let toolUseID, isToolEvent(eventName) else {
            return sessionID
        }

        return toolEventID(sessionID: sessionID, toolUseID: toolUseID)
    }

    private static func isToolEvent(_ eventName: String?) -> Bool {
        guard let eventName else {
            return false
        }

        return eventName.lowercased().contains("tool")
    }
}

private struct IncomingBridgePayload: Decodable {
    let event: String?
    let sessionID: String?
    let cwd: String?
    let model: String?
    let transcriptPath: String?
    let toolUseID: String?
    let stopHookActive: Bool?
    let lastAssistantMessage: String?
    let toolName: String?
    let toolInput: BridgeToolInput?
    let toolCommand: String?
    let prompt: String?
    let codexEventType: String?
    let codexPermissionMode: String?
    let permissionStatus: String?

    var requiresApproval: Bool {
        let eventName = (event ?? codexEventType ?? "").lowercased()
        return eventName == "pretooluse"
            || eventName == "hook-pre-tool-use"
            || eventName == "hook-pretooluse"
            || codexPermissionMode != nil
    }

    private enum CodingKeys: String, CodingKey {
        case event
        case sessionID = "session_id"
        case cwd
        case model
        case transcriptPath = "transcript_path"
        case toolUseID = "tool_use_id"
        case stopHookActive = "stop_hook_active"
        case lastAssistantMessage = "last_assistant_message"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolCommand = "tool_command"
        case prompt
        case codexEventType = "codex_event_type"
        case codexPermissionMode = "codex_permission_mode"
        case permissionStatus = "permission_status"
    }
}

private struct BridgeToolInput: Decodable {
    let command: String?
}
