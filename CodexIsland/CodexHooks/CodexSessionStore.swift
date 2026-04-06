import Foundation

struct CodexRecentSession: Identifiable, Equatable {
    let id: String
    let sessionID: String
    let projectName: String
    let updatedAt: Date
    let state: CodexSessionState
    let cwd: String
    let model: String
    let transcriptPath: String?
    let lastEvent: String?
    let lastUserPrompt: String?
    let lastAssistantMessage: String?
    let toolName: String?
    let toolUseID: String?
    let toolCommand: String?
    let requiresApproval: Bool
    let approvalStatus: String?
}

struct CodexToolCall: Identifiable, Equatable {
    let id: String
    let sessionID: String
    let updatedAt: Date
    let toolName: String?
    let toolUseID: String?
    let toolCommand: String?
    let requiresApproval: Bool
    let approvalStatus: String?
    let lastEvent: String?
}

struct CodexSessionGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let projectName: String
    let updatedAt: Date
    let state: CodexSessionState
    let cwd: String
    let model: String
    let transcriptPath: String?
    let lastEvent: String?
    let lastUserPrompt: String?
    let lastAssistantMessage: String?
    let toolCalls: [CodexToolCall]
}

enum CodexSessionState: Equatable {
    case running
    case idle
    case completed
    case unknown(String)

    var displayName: String {
        switch self {
        case .running:
            return "running"
        case .idle:
            return "idle"
        case .completed:
            return "completed"
        case .unknown(let value):
            return value
        }
    }
}

struct CodexSessionStore: CodexSessionPersisting {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let fileManager: FileManager
    private let storeURL: URL
    private let now: Date
    private let debugLogger: CodexHookDebugLogger

    init(
        storeURL: URL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("codex-island-hook-sessions.json"),
        fileManager: FileManager = .default,
        now: Date = Date(),
        debugLogger: CodexHookDebugLogger = CodexHookDebugLogger()
    ) {
        self.storeURL = storeURL
        self.fileManager = fileManager
        self.now = now
        self.debugLogger = debugLogger
    }

    func recentSessions(limit: Int = 8) throws -> [CodexRecentSession] {
        let sessions = try loadEntries()
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map {
                CodexRecentSession(
                    id: $0.id,
                    sessionID: $0.sessionID,
                    projectName: $0.title,
                    updatedAt: $0.updatedAt,
                    state: $0.sessionState,
                    cwd: $0.cwd,
                    model: $0.model,
                    transcriptPath: $0.transcriptPath,
                    lastEvent: $0.lastEvent,
                    lastUserPrompt: $0.lastUserPrompt,
                    lastAssistantMessage: $0.lastAssistantMessage,
                    toolName: $0.toolName,
                    toolUseID: $0.toolUseID,
                    toolCommand: $0.toolCommand,
                    requiresApproval: $0.requiresApproval,
                    approvalStatus: $0.approvalStatus
                )
            }

        debugLogger.log("recentSessions loaded \(sessions.count) sessions from \(storeURL.path)")
        return sessions
    }

    func record(_ invocation: CodexHookInvocation) throws {
        try persist(SessionRecord(invocation: invocation, updatedAt: now))
    }

    func recordPayloadData(_ data: Data) throws {
        if let invocation = try? CodexHookInvocation.decode(from: data) {
            debugLogger.log("recordPayloadData decoded raw Codex hook payload")
            try record(invocation)
            return
        }

        if let bridgePayload = try? Self.decoder.decode(CodexBridgePayload.self, from: data) {
            debugLogger.log("recordPayloadData decoded bridge payload event=\(bridgePayload.event ?? bridgePayload.codexEventType ?? "unknown")")
            try persist(SessionRecord(bridgePayload: bridgePayload, updatedAt: now))
            return
        }

        if
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let bridgePayload = CodexBridgePayload(dictionary: object)
        {
            debugLogger.log("recordPayloadData decoded bridge payload from dynamic JSON event=\(bridgePayload.event ?? bridgePayload.codexEventType ?? "unknown")")
            try persist(SessionRecord(bridgePayload: bridgePayload, updatedAt: now))
            return
        }

        let content = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        debugLogger.log("recordPayloadData could not decode payload: \(content)")
    }

    func updateApproval(sessionID: String, toolUseID: String, status: String) throws {
        var entries = try loadEntries()
        guard let index = entries.firstIndex(where: { $0.sessionID == sessionID && $0.toolUseID == toolUseID }) else {
            debugLogger.log("updateApproval could not find session \(sessionID) tool \(toolUseID)")
            return
        }

        entries[index].requiresApproval = false
        entries[index].approvalStatus = status
        try saveEntries(entries)
        debugLogger.log("updated approval status for \(sessionID) tool \(toolUseID) to \(status)")
    }

    private func persist(_ update: SessionRecord) throws {
        var entries = try loadEntries()

        if let index = entries.firstIndex(where: { $0.id == update.id }) {
            entries[index].merge(update)
        } else {
            entries.append(HookSessionEntry(record: update))
        }

        try saveEntries(entries)
        debugLogger.log("saved session \(update.id) state=\(update.state) title=\(update.title) to \(storeURL.path)")
    }

    private func loadEntries() throws -> [HookSessionEntry] {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            debugLogger.log("session store does not exist at \(storeURL.path)")
            return []
        }

        let data = try Data(contentsOf: storeURL)
        guard !data.isEmpty else {
            debugLogger.log("session store is empty at \(storeURL.path)")
            return []
        }

        let entries = try Self.decoder.decode([HookSessionEntry].self, from: data)
        debugLogger.log("decoded \(entries.count) stored sessions from \(storeURL.path)")
        return entries
    }

    private func saveEntries(_ entries: [HookSessionEntry]) throws {
        try fileManager.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data = try Self.encoder.encode(entries)
        try data.write(to: storeURL, options: .atomic)
    }
}

private struct HookSessionEntry: Codable, Equatable {
    let id: String
    let sessionID: String
    var title: String
    var updatedAt: Date
    var state: String
    var transcriptPath: String?
    var cwd: String
    var model: String
    var lastEvent: String?
    var lastUserPrompt: String?
    var lastAssistantMessage: String?
    var toolName: String?
    var toolUseID: String?
    var toolCommand: String?
    var requiresApproval: Bool
    var approvalStatus: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case title
        case updatedAt
        case state
        case transcriptPath
        case cwd
        case model
        case lastEvent
        case lastUserPrompt
        case lastAssistantMessage
        case toolName
        case toolUseID
        case toolCommand
        case requiresApproval
        case approvalStatus
    }

    init(record: SessionRecord) {
        id = record.id
        sessionID = record.sessionID
        title = record.title
        updatedAt = record.updatedAt
        state = record.state
        transcriptPath = record.transcriptPath
        cwd = record.cwd
        model = record.model
        lastEvent = record.lastEvent
        lastUserPrompt = record.lastUserPrompt
        lastAssistantMessage = record.lastAssistantMessage
        toolName = record.toolName
        toolUseID = record.toolUseID
        toolCommand = record.toolCommand
        requiresApproval = record.requiresApproval
        approvalStatus = record.approvalStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? id
        title = try container.decode(String.self, forKey: .title)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        state = try container.decode(String.self, forKey: .state)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd) ?? transcriptPath ?? "unknown"
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "unknown"
        lastEvent = try container.decodeIfPresent(String.self, forKey: .lastEvent)
        lastUserPrompt = try container.decodeIfPresent(String.self, forKey: .lastUserPrompt)
        lastAssistantMessage = try container.decodeIfPresent(String.self, forKey: .lastAssistantMessage)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        toolUseID = try container.decodeIfPresent(String.self, forKey: .toolUseID)
        toolCommand = try container.decodeIfPresent(String.self, forKey: .toolCommand)
        requiresApproval = try container.decodeIfPresent(Bool.self, forKey: .requiresApproval) ?? false
        approvalStatus = try container.decodeIfPresent(String.self, forKey: .approvalStatus)
    }

    var sessionState: CodexSessionState {
        switch state {
        case "running":
            return .running
        case "idle":
            return .idle
        case "completed":
            return .completed
        default:
            return .unknown(state)
        }
    }

    mutating func merge(_ record: SessionRecord) {
        title = record.title
        updatedAt = record.updatedAt
        state = record.state
        transcriptPath = record.transcriptPath ?? transcriptPath
        cwd = record.cwd
        model = record.model == "unknown" ? model : record.model
        lastEvent = record.lastEvent
        lastUserPrompt = record.lastUserPrompt ?? lastUserPrompt
        lastAssistantMessage = record.lastAssistantMessage ?? lastAssistantMessage
        toolName = record.toolName ?? toolName
        toolUseID = record.toolUseID ?? toolUseID
        toolCommand = record.toolCommand ?? toolCommand
        requiresApproval = record.requiresApproval
        approvalStatus = record.approvalStatus ?? approvalStatus
    }
}

private struct SessionRecord {
    let id: String
    let sessionID: String
    let title: String
    let updatedAt: Date
    let state: String
    let transcriptPath: String?
    let cwd: String
    let model: String
    let lastEvent: String?
    let lastUserPrompt: String?
    let lastAssistantMessage: String?
    let toolName: String?
    let toolUseID: String?
    let toolCommand: String?
    let requiresApproval: Bool
    let approvalStatus: String?

    init(invocation: CodexHookInvocation, updatedAt: Date) {
        switch invocation {
        case .sessionStart(let context):
            sessionID = context.sessionID
            id = context.sessionID
            title = Self.makeTitle(from: context.cwd)
            self.updatedAt = updatedAt
            state = "running"
            transcriptPath = context.transcriptPath
            cwd = context.cwd
            model = context.model
            lastEvent = context.hookEventName.rawValue
            lastUserPrompt = nil
            lastAssistantMessage = nil
            toolName = nil
            toolUseID = nil
            toolCommand = nil
            requiresApproval = false
            approvalStatus = nil
        case .preToolUse(let context):
            let requiresApproval = CodexCommandApprovalMatcher.requiresApproval(for: context)
            sessionID = context.sessionID
            id = Self.makeToolEventID(sessionID: context.sessionID, toolUseID: context.toolUseID)
            title = Self.makeTitle(from: context.cwd)
            self.updatedAt = updatedAt
            state = "running"
            transcriptPath = context.transcriptPath
            cwd = context.cwd
            model = context.model
            lastEvent = context.hookEventName.rawValue
            lastUserPrompt = nil
            lastAssistantMessage = nil
            toolName = context.toolName.displayName
            toolUseID = context.toolUseID
            toolCommand = context.toolInput.command
            self.requiresApproval = requiresApproval
            approvalStatus = requiresApproval ? "pending" : nil
        case .postToolUse(let context):
            sessionID = context.sessionID
            id = Self.makeToolEventID(sessionID: context.sessionID, toolUseID: context.toolUseID)
            title = Self.makeTitle(from: context.cwd)
            self.updatedAt = updatedAt
            state = "running"
            transcriptPath = context.transcriptPath
            cwd = context.cwd
            model = context.model
            lastEvent = context.hookEventName.rawValue
            lastUserPrompt = nil
            lastAssistantMessage = nil
            toolName = context.toolName.displayName
            toolUseID = context.toolUseID
            toolCommand = context.toolInput.command
            requiresApproval = false
            approvalStatus = nil
        case .userPromptSubmit(let context):
            sessionID = context.sessionID
            id = context.sessionID
            title = Self.makeTitle(from: context.cwd)
            self.updatedAt = updatedAt
            state = "running"
            transcriptPath = context.transcriptPath
            cwd = context.cwd
            model = context.model
            lastEvent = context.hookEventName.rawValue
            lastUserPrompt = context.prompt
            lastAssistantMessage = nil
            toolName = nil
            toolUseID = nil
            toolCommand = nil
            requiresApproval = false
            approvalStatus = nil
        case .stop(let context):
            sessionID = context.sessionID
            id = context.sessionID
            title = Self.makeTitle(from: context.cwd)
            self.updatedAt = updatedAt
            state = context.stopHookActive ? "running" : "completed"
            transcriptPath = context.transcriptPath
            cwd = context.cwd
            model = context.model
            lastEvent = context.hookEventName.rawValue
            lastUserPrompt = nil
            lastAssistantMessage = context.lastAssistantMessage
            toolName = nil
            toolUseID = nil
            toolCommand = nil
            requiresApproval = false
            approvalStatus = nil
        }
    }

    init(bridgePayload: CodexBridgePayload, updatedAt: Date) {
        let resolvedSessionID = bridgePayload.sessionID ?? UUID().uuidString
        sessionID = resolvedSessionID
        id = Self.makeEventID(
            sessionID: resolvedSessionID,
            toolUseID: bridgePayload.toolUseID,
            eventName: bridgePayload.codexEventType ?? bridgePayload.event
        )
        title = Self.makeTitle(from: bridgePayload.cwd ?? bridgePayload.transcriptPath ?? "unknown")
        self.updatedAt = updatedAt
        state = Self.state(from: bridgePayload)
        transcriptPath = bridgePayload.transcriptPath
        cwd = bridgePayload.cwd ?? transcriptPath ?? "unknown"
        model = bridgePayload.model ?? "unknown"
        lastEvent = bridgePayload.event ?? bridgePayload.codexEventType
        lastUserPrompt = bridgePayload.prompt
        lastAssistantMessage = bridgePayload.lastAssistantMessage ?? bridgePayload.codexLastAssistantMessage
        toolName = bridgePayload.toolName
        toolUseID = bridgePayload.toolUseID
        toolCommand = bridgePayload.toolInput?.command ?? bridgePayload.toolCommand
        requiresApproval = Self.requiresApproval(from: bridgePayload)
        approvalStatus = requiresApproval ? "pending" : bridgePayload.permissionStatus
    }

    private static func makeTitle(from cwd: String) -> String {
        let component = URL(fileURLWithPath: cwd).lastPathComponent
        return component.isEmpty ? cwd : component
    }

    private static func makeToolEventID(sessionID: String, toolUseID: String) -> String {
        "\(sessionID)::\(toolUseID)"
    }

    private static func makeEventID(sessionID: String, toolUseID: String?, eventName: String?) -> String {
        guard let toolUseID, isToolEvent(eventName) else {
            return sessionID
        }

        return makeToolEventID(sessionID: sessionID, toolUseID: toolUseID)
    }

    private static func isToolEvent(_ eventName: String?) -> Bool {
        guard let eventName else {
            return false
        }

        return eventName.lowercased().contains("tool")
    }

    private static func state(from payload: CodexBridgePayload) -> String {
        let eventName = payload.codexEventType ?? payload.event ?? ""
        let normalized = eventName.lowercased()

        if eventName == "Stop", payload.stopHookActive == false {
            return "completed"
        }

        if normalized == "stop" || normalized == "hook-stop" || normalized == "hook-session-stop" {
            return "completed"
        }

        return "running"
    }

    private static func requiresApproval(from payload: CodexBridgePayload) -> Bool {
        let eventName = (payload.codexEventType ?? payload.event ?? "").lowercased()

        if eventName == "pretooluse" || eventName == "hook-pre-tool-use" || eventName == "hook-pretooluse" {
            return true
        }

        if payload.codexPermissionMode != nil {
            return true
        }

        return false
    }
}

private struct CodexBridgePayload: Decodable {
    let event: String?
    let sessionID: String?
    let cwd: String?
    let model: String?
    let transcriptPath: String?
    let codexEventType: String?
    let stopHookActive: Bool?
    let lastAssistantMessage: String?
    let codexLastAssistantMessage: String?
    let prompt: String?
    let toolName: String?
    let toolUseID: String?
    let toolInput: BridgeToolInput?
    let toolCommand: String?
    let codexPermissionMode: String?
    let permissionStatus: String?

    init(
        event: String?,
        sessionID: String?,
        cwd: String?,
        model: String?,
        transcriptPath: String?,
        codexEventType: String?,
        stopHookActive: Bool?,
        lastAssistantMessage: String?,
        codexLastAssistantMessage: String?,
        prompt: String?,
        toolName: String?,
        toolUseID: String?,
        toolInput: BridgeToolInput?,
        toolCommand: String?,
        codexPermissionMode: String?,
        permissionStatus: String?
    ) {
        self.event = event
        self.sessionID = sessionID
        self.cwd = cwd
        self.model = model
        self.transcriptPath = transcriptPath
        self.codexEventType = codexEventType
        self.stopHookActive = stopHookActive
        self.lastAssistantMessage = lastAssistantMessage
        self.codexLastAssistantMessage = codexLastAssistantMessage
        self.prompt = prompt
        self.toolName = toolName
        self.toolUseID = toolUseID
        self.toolInput = toolInput
        self.toolCommand = toolCommand
        self.codexPermissionMode = codexPermissionMode
        self.permissionStatus = permissionStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decodeIfPresent(String.self, forKey: .event)
        sessionID =
            try container.decodeIfPresent(String.self, forKey: .sessionID)
            ?? container.decodeIfPresent(String.self, forKey: .session)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        transcriptPath =
            try container.decodeIfPresent(String.self, forKey: .transcriptPath)
            ?? container.decodeIfPresent(String.self, forKey: .codexTranscriptPath)
        codexEventType =
            try container.decodeIfPresent(String.self, forKey: .codexEventType)
            ?? container.decodeIfPresent(String.self, forKey: .hookEventName)
        stopHookActive = try container.decodeIfPresent(Bool.self, forKey: .stopHookActive)
        lastAssistantMessage = try container.decodeIfPresent(String.self, forKey: .lastAssistantMessage)
        codexLastAssistantMessage = try container.decodeIfPresent(String.self, forKey: .codexLastAssistantMessage)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        toolUseID = try container.decodeIfPresent(String.self, forKey: .toolUseID)
        toolInput = try container.decodeIfPresent(BridgeToolInput.self, forKey: .toolInput)
        toolCommand = try container.decodeIfPresent(String.self, forKey: .toolCommand)
        codexPermissionMode = try container.decodeIfPresent(String.self, forKey: .codexPermissionMode)
        permissionStatus = try container.decodeIfPresent(String.self, forKey: .permissionStatus)
    }

    init?(dictionary: [String: Any]) {
        event = dictionary["event"] as? String
        sessionID = dictionary["session_id"] as? String ?? dictionary["session"] as? String
        cwd = dictionary["cwd"] as? String
        model = dictionary["model"] as? String
        transcriptPath = dictionary["transcript_path"] as? String ?? dictionary["codex_transcript_path"] as? String
        codexEventType = dictionary["codex_event_type"] as? String ?? dictionary["hook_event_name"] as? String
        stopHookActive = dictionary["stop_hook_active"] as? Bool
        lastAssistantMessage = dictionary["last_assistant_message"] as? String
        codexLastAssistantMessage = dictionary["codex_last_assistant_message"] as? String
        prompt = dictionary["prompt"] as? String
        toolName = dictionary["tool_name"] as? String
        toolUseID = dictionary["tool_use_id"] as? String
        toolInput = BridgeToolInput(dictionary: dictionary["tool_input"] as? [String: Any])
        toolCommand = dictionary["tool_command"] as? String
        codexPermissionMode = dictionary["codex_permission_mode"] as? String
        permissionStatus = dictionary["permission_status"] as? String

        if event == nil, sessionID == nil, cwd == nil, transcriptPath == nil, codexEventType == nil {
            return nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case event
        case sessionID = "session_id"
        case session
        case cwd
        case model
        case transcriptPath = "transcript_path"
        case codexTranscriptPath = "codex_transcript_path"
        case codexEventType = "codex_event_type"
        case hookEventName = "hook_event_name"
        case stopHookActive = "stop_hook_active"
        case lastAssistantMessage = "last_assistant_message"
        case codexLastAssistantMessage = "codex_last_assistant_message"
        case prompt
        case toolName = "tool_name"
        case toolUseID = "tool_use_id"
        case toolInput = "tool_input"
        case toolCommand = "tool_command"
        case codexPermissionMode = "codex_permission_mode"
        case permissionStatus = "permission_status"
    }
}

private struct BridgeToolInput: Codable {
    let command: String?

    init(command: String?) {
        self.command = command
    }

    init?(dictionary: [String: Any]?) {
        guard let dictionary else {
            return nil
        }

        command = dictionary["command"] as? String
    }
}
