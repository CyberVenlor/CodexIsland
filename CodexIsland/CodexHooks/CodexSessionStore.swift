import Foundation

struct CodexRecentSession: Identifiable, Equatable {
    let id: String
    let title: String
    let updatedAt: Date
    let state: CodexSessionState
    let transcriptPath: String?
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
    private let fileManager: FileManager
    private let codexHomeURL: URL
    private let now: Date

    init(
        codexHomeURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex", isDirectory: true),
        fileManager: FileManager = .default,
        now: Date = Date()
    ) {
        self.codexHomeURL = codexHomeURL
        self.fileManager = fileManager
        self.now = now
    }

    func recentSessions(limit: Int = 8) throws -> [CodexRecentSession] {
        let indexEntries = try loadIndexEntries()
        let runningSessionIDs = loadRunningSessionIDs()
        let groupedTranscriptPaths = try transcriptPathsByID()

        return indexEntries
            .prefix(limit)
            .map { entry in
                let transcriptPath = groupedTranscriptPaths[entry.id]
                let state = sessionState(
                    id: entry.id,
                    transcriptPath: transcriptPath,
                    isRunning: runningSessionIDs.contains(entry.id)
                )

                return CodexRecentSession(
                    id: entry.id,
                    title: entry.threadName,
                    updatedAt: entry.updatedAt,
                    state: state,
                    transcriptPath: transcriptPath?.path
                )
            }
    }

    private func loadIndexEntries() throws -> [SessionIndexEntry] {
        let indexURL = codexHomeURL.appendingPathComponent("session_index.jsonl")
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return []
        }

        let data = try Data(contentsOf: indexURL)
        let content = String(decoding: data, as: UTF8.self)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try content
            .split(whereSeparator: \.isNewline)
            .map { line in
                try decoder.decode(SessionIndexEntry.self, from: Data(line.utf8))
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func loadRunningSessionIDs() -> Set<String> {
        let stateURL = codexHomeURL.appendingPathComponent(".codex-global-state.json")
        guard
            let data = try? Data(contentsOf: stateURL),
            let globalState = try? JSONDecoder().decode(CodexGlobalState.self, from: data)
        else {
            return []
        }

        return Set(
            globalState.electronPersistedAtomState.terminalOpenByKey
                .filter(\.value)
                .map(\.key)
        )
    }

    private func transcriptPathsByID() throws -> [String: URL] {
        let sessionsURL = codexHomeURL.appendingPathComponent("sessions", isDirectory: true)
        guard fileManager.fileExists(atPath: sessionsURL.path) else {
            return [:]
        }

        let transcriptURLs = try fileManager.subpathsOfDirectory(atPath: sessionsURL.path)
            .filter { $0.hasSuffix(".jsonl") }
            .map { sessionsURL.appendingPathComponent($0) }

        var result: [String: URL] = [:]

        for url in transcriptURLs {
            guard let id = sessionID(fromTranscriptURL: url) else {
                continue
            }

            if let current = result[id] {
                let currentDate = (try? modificationDate(for: current)) ?? .distantPast
                let candidateDate = (try? modificationDate(for: url)) ?? .distantPast

                if candidateDate > currentDate {
                    result[id] = url
                }
            } else {
                result[id] = url
            }
        }

        return result
    }

    private func sessionState(id: String, transcriptPath: URL?, isRunning: Bool) -> CodexSessionState {
        if isRunning {
            return .running
        }

        guard let transcriptPath else {
            return .idle
        }

        guard let lastEvent = loadLastEvent(from: transcriptPath) else {
            return .idle
        }

        if lastEvent.type == "event_msg", lastEvent.payloadType == "task_complete" {
            return .completed
        }

        if lastEvent.type == "response_item", lastEvent.payloadStatus == "completed" {
            return .completed
        }

        if isRecentlyUpdated(transcriptPath) {
            return .running
        }

        return .idle
    }

    private func loadLastEvent(from url: URL) -> TranscriptEvent? {
        guard
            let data = try? Data(contentsOf: url),
            let content = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let decoder = JSONDecoder()

        for line in content.split(whereSeparator: \.isNewline).reversed() {
            guard let event = try? decoder.decode(TranscriptEvent.self, from: Data(line.utf8)) else {
                continue
            }

            if event.type == "event_msg", event.payloadType == "token_count" {
                continue
            }

            return event
        }

        return nil
    }

    private func isRecentlyUpdated(_ url: URL) -> Bool {
        guard let modifiedAt = try? modificationDate(for: url) else {
            return false
        }

        return now.timeIntervalSince(modifiedAt) < 120
    }

    private func modificationDate(for url: URL) throws -> Date {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return values.contentModificationDate ?? .distantPast
    }

    private func sessionID(fromTranscriptURL url: URL) -> String? {
        guard
            let data = try? Data(contentsOf: url),
            let firstLine = String(data: data, encoding: .utf8)?
                .split(whereSeparator: \.isNewline)
                .first
        else {
            return nil
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode(SessionMetaEnvelope.self, from: Data(firstLine.utf8)))?.payload.id
    }
}

private struct SessionIndexEntry: Decodable {
    let id: String
    let threadName: String
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
        case updatedAt = "updated_at"
    }
}

private struct CodexGlobalState: Decodable {
    let electronPersistedAtomState: ElectronPersistedAtomState

    private enum CodingKeys: String, CodingKey {
        case electronPersistedAtomState = "electron-persisted-atom-state"
    }
}

private struct ElectronPersistedAtomState: Decodable {
    let terminalOpenByKey: [String: Bool]

    private enum CodingKeys: String, CodingKey {
        case terminalOpenByKey = "terminal-open-by-key"
    }
}

private struct SessionMetaEnvelope: Decodable {
    let payload: SessionMetaPayload
}

private struct SessionMetaPayload: Decodable {
    let id: String
}

private struct TranscriptEvent: Decodable {
    let type: String
    let payloadType: String?
    let payloadStatus: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum PayloadCodingKeys: String, CodingKey {
        case type
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)

        if let payloadContainer = try? container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .payload) {
            payloadType = try payloadContainer.decodeIfPresent(String.self, forKey: .type)
            payloadStatus = try payloadContainer.decodeIfPresent(String.self, forKey: .status)
        } else {
            payloadType = nil
            payloadStatus = nil
        }
    }
}
