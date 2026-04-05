import Foundation

enum CodexHookEventName: String, Codable, CaseIterable {
    case sessionStart = "SessionStart"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case userPromptSubmit = "UserPromptSubmit"
    case stop = "Stop"
}

enum CodexSessionStartSource: Codable, Equatable {
    case startup
    case resume
    case clear
    case other(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "startup":
            self = .startup
        case "resume":
            self = .resume
        case "clear":
            self = .clear
        default:
            self = .other(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .startup:
            try container.encode("startup")
        case .resume:
            try container.encode("resume")
        case .clear:
            try container.encode("clear")
        case .other(let value):
            try container.encode(value)
        }
    }
}

enum CodexPermissionMode: Codable, Equatable {
    case `default`
    case acceptEdits
    case plan
    case dontAsk
    case bypassPermissions
    case other(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "default":
            self = .default
        case "acceptEdits":
            self = .acceptEdits
        case "plan":
            self = .plan
        case "dontAsk":
            self = .dontAsk
        case "bypassPermissions":
            self = .bypassPermissions
        default:
            self = .other(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .default:
            try container.encode("default")
        case .acceptEdits:
            try container.encode("acceptEdits")
        case .plan:
            try container.encode("plan")
        case .dontAsk:
            try container.encode("dontAsk")
        case .bypassPermissions:
            try container.encode("bypassPermissions")
        case .other(let value):
            try container.encode(value)
        }
    }
}

enum CodexToolName: Codable, Equatable {
    case bash
    case other(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "Bash":
            self = .bash
        default:
            self = .other(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .bash:
            try container.encode("Bash")
        case .other(let value):
            try container.encode(value)
        }
    }
}

enum CodexPermissionDecision: String, Codable, Equatable {
    case allow
    case ask
    case deny
}

enum CodexHookDecision: String, Codable, Equatable {
    case block
    case approve
}

enum CodexJSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: CodexJSONValue])
    case array([CodexJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: CodexJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([CodexJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct CodexToolInput: Codable, Equatable {
    let command: String
}

protocol CodexHookContext {
    var sessionID: String { get }
    var transcriptPath: String? { get }
    var cwd: String { get }
    var hookEventName: CodexHookEventName { get }
    var model: String { get }
}

struct CodexSessionStartContext: Codable, Equatable, CodexHookContext {
    let sessionID: String
    let transcriptPath: String?
    let cwd: String
    let hookEventName: CodexHookEventName
    let model: String
    let permissionMode: CodexPermissionMode?
    let source: CodexSessionStartSource

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case hookEventName = "hook_event_name"
        case model
        case permissionMode = "permission_mode"
        case source
    }
}

struct CodexPreToolUseContext: Codable, Equatable, CodexHookContext {
    let sessionID: String
    let transcriptPath: String?
    let cwd: String
    let hookEventName: CodexHookEventName
    let model: String
    let permissionMode: CodexPermissionMode?
    let turnID: String
    let toolName: CodexToolName
    let toolUseID: String
    let toolInput: CodexToolInput

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case hookEventName = "hook_event_name"
        case model
        case permissionMode = "permission_mode"
        case turnID = "turn_id"
        case toolName = "tool_name"
        case toolUseID = "tool_use_id"
        case toolInput = "tool_input"
    }
}

struct CodexPostToolUseContext: Codable, Equatable, CodexHookContext {
    let sessionID: String
    let transcriptPath: String?
    let cwd: String
    let hookEventName: CodexHookEventName
    let model: String
    let permissionMode: CodexPermissionMode?
    let turnID: String
    let toolName: CodexToolName
    let toolUseID: String
    let toolInput: CodexToolInput
    let toolResponse: CodexJSONValue

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case hookEventName = "hook_event_name"
        case model
        case permissionMode = "permission_mode"
        case turnID = "turn_id"
        case toolName = "tool_name"
        case toolUseID = "tool_use_id"
        case toolInput = "tool_input"
        case toolResponse = "tool_response"
    }
}

struct CodexUserPromptSubmitContext: Codable, Equatable, CodexHookContext {
    let sessionID: String
    let transcriptPath: String?
    let cwd: String
    let hookEventName: CodexHookEventName
    let model: String
    let permissionMode: CodexPermissionMode?
    let turnID: String
    let prompt: String

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case hookEventName = "hook_event_name"
        case model
        case permissionMode = "permission_mode"
        case turnID = "turn_id"
        case prompt
    }
}

struct CodexStopContext: Codable, Equatable, CodexHookContext {
    let sessionID: String
    let transcriptPath: String?
    let cwd: String
    let hookEventName: CodexHookEventName
    let model: String
    let permissionMode: CodexPermissionMode?
    let turnID: String
    let stopHookActive: Bool
    let lastAssistantMessage: String?

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case hookEventName = "hook_event_name"
        case model
        case permissionMode = "permission_mode"
        case turnID = "turn_id"
        case stopHookActive = "stop_hook_active"
        case lastAssistantMessage = "last_assistant_message"
    }
}

enum CodexHookInvocation: Equatable {
    case sessionStart(CodexSessionStartContext)
    case preToolUse(CodexPreToolUseContext)
    case postToolUse(CodexPostToolUseContext)
    case userPromptSubmit(CodexUserPromptSubmitContext)
    case stop(CodexStopContext)

    var hookEventName: CodexHookEventName {
        switch self {
        case .sessionStart:
            return .sessionStart
        case .preToolUse:
            return .preToolUse
        case .postToolUse:
            return .postToolUse
        case .userPromptSubmit:
            return .userPromptSubmit
        case .stop:
            return .stop
        }
    }

    static func decode(from data: Data, using decoder: JSONDecoder = JSONDecoder()) throws -> Self {
        let event = try decoder.decode(CodexHookEventEnvelope.self, from: data)

        switch event.hookEventName {
        case .sessionStart:
            return .sessionStart(try decoder.decode(CodexSessionStartContext.self, from: data))
        case .preToolUse:
            return .preToolUse(try decoder.decode(CodexPreToolUseContext.self, from: data))
        case .postToolUse:
            return .postToolUse(try decoder.decode(CodexPostToolUseContext.self, from: data))
        case .userPromptSubmit:
            return .userPromptSubmit(try decoder.decode(CodexUserPromptSubmitContext.self, from: data))
        case .stop:
            return .stop(try decoder.decode(CodexStopContext.self, from: data))
        }
    }
}

struct CodexHookSpecificOutput: Codable, Equatable {
    let hookEventName: CodexHookEventName
    let additionalContext: String?
    let permissionDecision: CodexPermissionDecision?
    let permissionDecisionReason: String?
}

struct CodexHookResponse: Codable, Equatable {
    var shouldContinue: Bool? = nil
    var stopReason: String? = nil
    var systemMessage: String? = nil
    var suppressOutput: Bool? = nil
    var decision: CodexHookDecision? = nil
    var reason: String? = nil
    var hookSpecificOutput: CodexHookSpecificOutput? = nil

    private enum CodingKeys: String, CodingKey {
        case shouldContinue = "continue"
        case stopReason
        case systemMessage
        case suppressOutput
        case decision
        case reason
        case hookSpecificOutput
    }

    static func sessionStart(additionalContext: String? = nil, systemMessage: String? = nil) -> Self {
        Self(
            systemMessage: systemMessage,
            hookSpecificOutput: CodexHookSpecificOutput(
                hookEventName: .sessionStart,
                additionalContext: additionalContext,
                permissionDecision: nil,
                permissionDecisionReason: nil
            )
        )
    }

    static func denyToolUse(reason: String, systemMessage: String? = nil) -> Self {
        Self(
            systemMessage: systemMessage,
            decision: .block,
            reason: reason,
            hookSpecificOutput: CodexHookSpecificOutput(
                hookEventName: .preToolUse,
                additionalContext: nil,
                permissionDecision: .deny,
                permissionDecisionReason: reason
            )
        )
    }

    static func approveToolUse(reason: String? = nil, systemMessage: String? = nil) -> Self {
        Self(
            systemMessage: systemMessage,
            decision: .approve,
            reason: reason,
            hookSpecificOutput: CodexHookSpecificOutput(
                hookEventName: .preToolUse,
                additionalContext: nil,
                permissionDecision: .allow,
                permissionDecisionReason: reason
            )
        )
    }

    static func postToolUseFeedback(
        reason: String,
        additionalContext: String? = nil,
        systemMessage: String? = nil,
        continue shouldContinue: Bool? = nil,
        stopReason: String? = nil
    ) -> Self {
        Self(
            shouldContinue: shouldContinue,
            stopReason: stopReason,
            systemMessage: systemMessage,
            decision: .block,
            reason: reason,
            hookSpecificOutput: CodexHookSpecificOutput(
                hookEventName: .postToolUse,
                additionalContext: additionalContext,
                permissionDecision: nil,
                permissionDecisionReason: nil
            )
        )
    }

    static func blockUserPrompt(
        reason: String,
        additionalContext: String? = nil,
        systemMessage: String? = nil
    ) -> Self {
        Self(
            systemMessage: systemMessage,
            decision: .block,
            reason: reason,
            hookSpecificOutput: CodexHookSpecificOutput(
                hookEventName: .userPromptSubmit,
                additionalContext: additionalContext,
                permissionDecision: nil,
                permissionDecisionReason: nil
            )
        )
    }

    static func sessionEndContinue(reason: String, systemMessage: String? = nil) -> Self {
        Self(
            systemMessage: systemMessage,
            decision: .block,
            reason: reason
        )
    }

    func merging(_ other: CodexHookResponse) -> CodexHookResponse {
        CodexHookResponse(
            shouldContinue: other.shouldContinue ?? shouldContinue,
            stopReason: other.stopReason ?? stopReason,
            systemMessage: other.systemMessage ?? systemMessage,
            suppressOutput: other.suppressOutput ?? suppressOutput,
            decision: other.decision ?? decision,
            reason: other.reason ?? reason,
            hookSpecificOutput: other.hookSpecificOutput ?? hookSpecificOutput
        )
    }
}

private struct CodexHookEventEnvelope: Decodable {
    let hookEventName: CodexHookEventName

    private enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
    }
}
