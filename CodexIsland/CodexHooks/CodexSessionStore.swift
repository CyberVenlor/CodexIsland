import Foundation

struct CodexRecentSession: Identifiable, Equatable {
    let id: String
    let title: String
    let updatedAt: Date
    let state: CodexSessionState
    let cwd: String
    let model: String
    let transcriptPath: String?
    let lastEvent: String?
    let lastAssistantMessage: String?
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

struct CodexSessionStore {
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
                    title: $0.title,
                    updatedAt: $0.updatedAt,
                    state: $0.sessionState,
                    cwd: $0.cwd,
                    model: $0.model,
                    transcriptPath: $0.transcriptPath,
                    lastEvent: $0.lastEvent,
                    lastAssistantMessage: $0.lastAssistantMessage
                )
            }

        debugLogger.log("recentSessions loaded \(sessions.count) sessions from \(storeURL.path)")
        return sessions
    }

    func record(_ invocation: CodexHookInvocation) throws {
        let update = SessionRecord(invocation: invocation, updatedAt: now)
        try persist(update)
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
    var title: String
    var updatedAt: Date
    var state: String
    var transcriptPath: String?
    var cwd: String
    var model: String
    var lastEvent: String?
    var lastAssistantMessage: String?

    init(record: SessionRecord) {
        id = record.id
        title = record.title
        updatedAt = record.updatedAt
        state = record.state
        transcriptPath = record.transcriptPath
        cwd = record.cwd
        model = record.model
        lastEvent = record.lastEvent
        lastAssistantMessage = record.lastAssistantMessage
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
        lastAssistantMessage = record.lastAssistantMessage ?? lastAssistantMessage
    }
}

private struct SessionRecord {
    let id: String
    let title: String
    let updatedAt: Date
    let state: String
    let transcriptPath: String?
    let cwd: String
    let model: String
    let lastEvent: String?
    let lastAssistantMessage: String?

    init(invocation: CodexHookInvocation, updatedAt: Date) {
        switch invocation {
        case .sessionStart(let context):
            id = context.sessionID
            title = Self.makeTitle(from: context.cwd)
            self.updatedAt = updatedAt
            state = "running"
            transcriptPath = context.transcriptPath
            cwd = context.cwd
            model = context.model
            lastEvent = context.hookEventName.rawValue
            lastAssistantMessage = nil
        case .preToolUse(let context):
            id = context.sessionID
            title = Self.makeTitle(from: context.cwd)
            self.updatedAt = updatedAt
            state = "running"
            transcriptPath = context.transcriptPath
            cwd = context.cwd
            model = context.model
            lastEvent = context.hookEventName.rawValue
            lastAssistantMessage = nil
        case .postToolUse(let context):
            id = context.sessionID
            title = Self.makeTitle(from: context.cwd)
            self.updatedAt = updatedAt
            state = "running"
            transcriptPath = context.transcriptPath
            cwd = context.cwd
            model = context.model
            lastEvent = context.hookEventName.rawValue
            lastAssistantMessage = nil
        case .stop(let context):
            id = context.sessionID
            title = Self.makeTitle(from: context.cwd)
            self.updatedAt = updatedAt
            state = context.stopHookActive ? "running" : "completed"
            transcriptPath = context.transcriptPath
            cwd = context.cwd
            model = context.model
            lastEvent = context.hookEventName.rawValue
            lastAssistantMessage = context.lastAssistantMessage
        }
    }

    init(bridgePayload: CodexBridgePayload, updatedAt: Date) {
        id = bridgePayload.sessionID ?? UUID().uuidString
        title = Self.makeTitle(from: bridgePayload.cwd ?? bridgePayload.transcriptPath ?? "unknown")
        self.updatedAt = updatedAt
        state = Self.state(from: bridgePayload)
        transcriptPath = bridgePayload.transcriptPath
        cwd = bridgePayload.cwd ?? transcriptPath ?? "unknown"
        model = bridgePayload.model ?? "unknown"
        lastEvent = bridgePayload.event ?? bridgePayload.codexEventType
        lastAssistantMessage = bridgePayload.lastAssistantMessage ?? bridgePayload.codexLastAssistantMessage
    }

    private static func makeTitle(from cwd: String) -> String {
        let component = URL(fileURLWithPath: cwd).lastPathComponent
        return component.isEmpty ? cwd : component
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

    init(
        event: String?,
        sessionID: String?,
        cwd: String?,
        model: String?,
        transcriptPath: String?,
        codexEventType: String?,
        stopHookActive: Bool?,
        lastAssistantMessage: String?,
        codexLastAssistantMessage: String?
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
    }
}
