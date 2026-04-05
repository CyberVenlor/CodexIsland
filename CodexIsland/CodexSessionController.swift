import Darwin
import Combine
import Foundation

@MainActor
final class CodexSessionController: ObservableObject {
    @Published private(set) var sessions: [CodexSessionGroup] = []

    private let persistence: CodexSessionPersisting
    private let threadNameStore: CodexSessionThreadNameStore
    private let debugLogger: CodexHookDebugLogger
    private let launchedAt: Date
    private var pendingApprovalClients: [String: Int32] = [:]
    private var approvalQueue: [String] = []
    private var sessionIndex: [String: CodexRecentSession] = [:]

    init(
        persistence: CodexSessionPersisting = NoOpCodexSessionPersistence(),
        threadNameStore: CodexSessionThreadNameStore = CodexSessionThreadNameStore(),
        debugLogger: CodexHookDebugLogger = .disabled,
        launchedAt: Date = Date()
    ) {
        self.persistence = persistence
        self.threadNameStore = threadNameStore
        self.debugLogger = debugLogger
        self.launchedAt = launchedAt
    }

    func handleIncomingPayload(_ data: Data, client: Int32) -> CodexHookRelayServer.PayloadDisposition {
        let pendingApproval = PendingApproval.decode(from: data)

        if let session = CodexSessionProjection.session(from: data) {
            upsert(session: session, pendingApprovalKey: pendingApproval?.key)
        } else {
            debugLogger.log("failed to project incoming payload into session")
        }

        do {
            try persistence.recordPayloadData(data)
        } catch {
            debugLogger.log("failed to record incoming payload: \(error.localizedDescription)")
        }

        guard let pendingApproval else {
            return .closeClient
        }

        pendingApprovalClients[pendingApproval.key] = client
        if !approvalQueue.contains(pendingApproval.key) {
            approvalQueue.append(pendingApproval.key)
            publishVisibleSessions()
        }
        debugLogger.log("registered pending approval for \(pendingApproval.key)")
        return .holdClient
    }

    func approve(_ session: CodexRecentSession) {
        resolve(
            session,
            relayResponse: .approve,
            approvalStatus: "approved"
        )
    }

    func deny(_ session: CodexRecentSession) {
        do {
            resolve(
                session,
                relayResponse: .deny(
                    CodexHookResponse.denyToolUse(reason: "Denied from CodexIsland")
                ),
                approvalStatus: "denied"
            )
        } catch {
            debugLogger.log("failed to encode deny response for \(session.id): \(error.localizedDescription)")
        }
    }

    func approve(_ toolCall: CodexToolCall) {
        resolve(toolCall, approvalStatus: "approved", relayResponse: .approve)
    }

    func deny(_ toolCall: CodexToolCall) {
        resolve(
            toolCall,
            approvalStatus: "denied",
            relayResponse: .deny(
                CodexHookResponse.denyToolUse(reason: "Denied from CodexIsland")
            )
        )
    }

    private func resolve(
        _ session: CodexRecentSession,
        relayResponse: CodexHookRelayResponse,
        approvalStatus: String
    ) {
        guard
            let key = approvalKey(for: session),
            let client = pendingApprovalClients.removeValue(forKey: key)
        else {
            debugLogger.log("no pending approval client for session \(session.id)")
            return
        }

        do {
            let data = try JSONEncoder().encode(relayResponse)
            try FileHandle(fileDescriptor: client, closeOnDealloc: false).write(contentsOf: data)
            debugLogger.log("wrote relay response for \(key) decision=\(relayResponse.decision.rawValue)")
        } catch {
            debugLogger.log("failed to write relay response for \(key): \(error.localizedDescription)")
        }

        close(client)

        if let toolUseID = session.toolUseID {
            do {
                try persistence.updateApproval(sessionID: session.sessionID, toolUseID: toolUseID, status: approvalStatus)
            } catch {
                debugLogger.log("failed to persist approval status for \(key): \(error.localizedDescription)")
            }
        }

        removeResolvedToolCall(withID: session.id, approvalKey: key)
    }

    private func resolve(
        _ toolCall: CodexToolCall,
        approvalStatus: String,
        relayResponse: CodexHookRelayResponse
    ) {
        guard
            let toolUseID = toolCall.toolUseID,
            let client = pendingApprovalClients.removeValue(forKey: toolCall.id)
        else {
            debugLogger.log("no pending approval client for tool call \(toolCall.id)")
            return
        }

        do {
            let data = try JSONEncoder().encode(relayResponse)
            try FileHandle(fileDescriptor: client, closeOnDealloc: false).write(contentsOf: data)
            debugLogger.log("wrote relay response for \(toolCall.id) decision=\(relayResponse.decision.rawValue)")
        } catch {
            debugLogger.log("failed to write relay response for \(toolCall.id): \(error.localizedDescription)")
        }

        close(client)

        do {
            try persistence.updateApproval(sessionID: toolCall.sessionID, toolUseID: toolUseID, status: approvalStatus)
        } catch {
            debugLogger.log("failed to persist approval status for \(toolCall.id): \(error.localizedDescription)")
        }

        removeResolvedToolCall(withID: toolCall.id, approvalKey: toolCall.id)
    }

    private func upsert(session: CodexRecentSession, pendingApprovalKey: String? = nil) {
        guard session.updatedAt >= launchedAt else {
            return
        }

        if let existing = sessionIndex[session.id] {
            sessionIndex[session.id] = CodexSessionProjection.merge(existing: existing, update: session)
        } else {
            sessionIndex[session.id] = session
        }

        if let pendingApprovalKey, !approvalQueue.contains(pendingApprovalKey) {
            approvalQueue.append(pendingApprovalKey)
        }

        publishVisibleSessions()
    }

    private func approvalKey(for session: CodexRecentSession) -> String? {
        guard let toolUseID = session.toolUseID else {
            return nil
        }

        return "\(session.sessionID)::\(toolUseID)"
    }

    private func groupedSessions(from rawSessions: Dictionary<String, CodexRecentSession>.Values) -> [CodexSessionGroup] {
        let grouped = Dictionary(grouping: rawSessions, by: \.sessionID)
        let threadNames = threadNameStore.threadNamesBySessionID()

        return grouped.compactMap { sessionID, items in
            guard let base = items
                .sorted(by: { $0.updatedAt > $1.updatedAt })
                .first(where: { $0.id == sessionID }) ?? items.max(by: { $0.updatedAt < $1.updatedAt })
            else {
                return nil
            }

            let toolCalls = items
                .filter { $0.toolUseID != nil }
                .sorted { $0.updatedAt > $1.updatedAt }
                .map {
                    CodexToolCall(
                        id: $0.id,
                        sessionID: $0.sessionID,
                        updatedAt: $0.updatedAt,
                        toolName: $0.toolName,
                        toolUseID: $0.toolUseID,
                        toolCommand: $0.toolCommand,
                        requiresApproval: $0.requiresApproval,
                        approvalStatus: $0.approvalStatus,
                        lastEvent: $0.lastEvent
                    )
                }

            return CodexSessionGroup(
                id: sessionID,
                title: sessionTitle(for: base, threadName: threadNames[sessionID]),
                projectName: base.projectName,
                updatedAt: max(base.updatedAt, toolCalls.map(\.updatedAt).max() ?? base.updatedAt),
                state: base.state,
                cwd: base.cwd,
                model: base.model,
                transcriptPath: base.transcriptPath,
                lastEvent: base.lastEvent,
                lastUserPrompt: base.lastUserPrompt,
                lastAssistantMessage: base.lastAssistantMessage,
                toolCalls: toolCalls
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
        .prefix(12)
        .map { $0 }
    }

    private func publishVisibleSessions() {
        while let firstKey = approvalQueue.first, sessionIndex[firstKey] == nil {
            approvalQueue.removeFirst()
        }

        let visibleToolID = approvalQueue.first

        sessions = groupedSessions(from: sessionIndex.values)
            .map { group in
                CodexSessionGroup(
                    id: group.id,
                    title: group.title,
                    projectName: group.projectName,
                    updatedAt: group.updatedAt,
                    state: group.state,
                    cwd: group.cwd,
                    model: group.model,
                    transcriptPath: group.transcriptPath,
                    lastEvent: group.lastEvent,
                    lastUserPrompt: group.lastUserPrompt,
                    lastAssistantMessage: group.lastAssistantMessage,
                    toolCalls: group.toolCalls.filter { $0.id == visibleToolID }
                )
            }
    }

    private func removeResolvedToolCall(withID id: String, approvalKey: String) {
        sessionIndex.removeValue(forKey: id)
        approvalQueue.removeAll { $0 == approvalKey }
        publishVisibleSessions()
    }

    private func sessionTitle(for session: CodexRecentSession, threadName: String?) -> String {
        if let threadName, !threadName.isEmpty {
            return threadName
        }

        if let lastUserPrompt = sanitizedTitle(session.lastUserPrompt) {
            return lastUserPrompt
        }

        return session.projectName
    }

    private func sanitizedTitle(_ title: String?) -> String? {
        guard let title else {
            return nil
        }

        let singleLine = title
            .split(whereSeparator: \.isNewline)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let singleLine, !singleLine.isEmpty else {
            return nil
        }

        let maxLength = 72
        guard singleLine.count > maxLength else {
            return singleLine
        }

        let endIndex = singleLine.index(singleLine.startIndex, offsetBy: maxLength)
        return "\(singleLine[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)…"
    }
}

private struct CodexHookRelayResponse: Codable {
    let decision: RelayDecision
    let hookResponse: CodexHookResponse?

    enum RelayDecision: String, Codable {
        case approve
        case deny
    }

    static let approve = CodexHookRelayResponse(decision: .approve, hookResponse: nil)

    static func deny(_ hookResponse: CodexHookResponse) -> CodexHookRelayResponse {
        CodexHookRelayResponse(decision: .deny, hookResponse: hookResponse)
    }
}

private struct PendingApproval {
    let sessionID: String
    let toolUseID: String

    var key: String {
        "\(sessionID)::\(toolUseID)"
    }

    static func decode(from data: Data) -> PendingApproval? {
        guard
            let invocation = try? CodexHookInvocation.decode(from: data),
            case .preToolUse(let context) = invocation
        else {
            return nil
        }

        return PendingApproval(sessionID: context.sessionID, toolUseID: context.toolUseID)
    }
}
