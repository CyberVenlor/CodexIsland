import Darwin
import Combine
import Foundation

@MainActor
final class CodexSessionController: ObservableObject {
    @Published private(set) var sessions: [CodexSessionGroup] = []
    @Published private(set) var runningSessionCount: Int = 0

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

        syncApprovalTracking(for: session)

        publishVisibleSessions()
    }

    private func approvalKey(for session: CodexRecentSession) -> String? {
        guard let toolUseID = session.toolUseID else {
            return nil
        }

        return "\(session.sessionID)::\(toolUseID)"
    }

    private func allSessionGroups(from rawSessions: Dictionary<String, CodexRecentSession>.Values) -> [CodexSessionGroup] {
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
    }

    private func sortedSessionGroups(_ groups: [CodexSessionGroup]) -> [CodexSessionGroup] {
        groups.sorted {
            let lhsPriority = sessionSortPriority(for: $0.state)
            let rhsPriority = sessionSortPriority(for: $1.state)

            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }

            return $0.updatedAt > $1.updatedAt
        }
        .prefix(12)
        .map { $0 }
    }

    private func sessionSortPriority(for state: CodexSessionState) -> Int {
        switch state {
        case .running:
            return 0
        case .idle:
            return 1
        case .completed:
            return 2
        case .unknown:
            return 3
        }
    }

    private func publishVisibleSessions() {
        while let firstKey = approvalQueue.first, shouldDropApprovalTracking(forKey: firstKey) {
            approvalQueue.removeFirst()
        }

        let visibleToolID = approvalQueue.first
        let allGroups = allSessionGroups(from: sessionIndex.values)
        runningSessionCount = allGroups.filter { $0.state == .running }.count

        sessions = sortedSessionGroups(allGroups)
            .prefix(12)
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
        pendingApprovalClients.removeValue(forKey: approvalKey)
        approvalQueue.removeAll { $0 == approvalKey }
        publishVisibleSessions()
    }

    private func syncApprovalTracking(for session: CodexRecentSession) {
        guard let toolUseID = session.toolUseID else {
            return
        }

        let approvalKey = "\(session.sessionID)::\(toolUseID)"
        guard !session.requiresApproval else {
            return
        }

        pendingApprovalClients.removeValue(forKey: approvalKey)
        approvalQueue.removeAll { $0 == approvalKey }
    }

    private func shouldDropApprovalTracking(forKey key: String) -> Bool {
        guard let session = sessionIndex[key] else {
            pendingApprovalClients.removeValue(forKey: key)
            return true
        }

        guard session.requiresApproval else {
            pendingApprovalClients.removeValue(forKey: key)
            return true
        }

        return false
    }

    private func sessionTitle(for session: CodexRecentSession, threadName: String?) -> String {
        if let threadName, !threadName.isEmpty {
            return threadName
        }

        return session.projectName
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
