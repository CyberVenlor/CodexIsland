import Darwin
import Combine
import Foundation

@MainActor
final class CodexSessionController: ObservableObject {
    @Published private(set) var sessions: [CodexSessionGroup] = []
    @Published private(set) var runningSessionCount: Int = 0
    @Published private(set) var pendingApprovalToolCall: CodexToolCall?
    @Published private(set) var approvalDecisionCounts = ApprovalDecisionCounts()
    @Published private(set) var sessionEndedNotification: SessionEndedNotification?
    @Published private(set) var suspiciousSessionNotification: SuspiciousSessionNotification?

    private let persistence: CodexSessionPersisting
    private let threadNameStore: CodexSessionThreadNameStore
    private let sessionNavigator: CodexSessionNavigating
    private let debugLogger: CodexHookDebugLogger
    private let launchedAt: Date
    private let autoDenyLeadTime: TimeInterval
    private var pendingApprovalClients: [String: Int32] = [:]
    private var approvalQueue: [String] = []
    private var sessionIndex: [String: CodexRecentSession] = [:]
    private var approvalTimeoutTasks: [String: Task<Void, Never>] = [:]
    private var suspiciousSessionTasks: [String: Task<Void, Never>] = [:]
    private var preToolUseTimeout: TimeInterval = 300
    private var suspiciousSessionTimeout: TimeInterval = 60
    private var showSessionEndNotifications = true

    init(
        persistence: CodexSessionPersisting = NoOpCodexSessionPersistence(),
        threadNameStore: CodexSessionThreadNameStore = CodexSessionThreadNameStore(),
        sessionNavigator: CodexSessionNavigating = CodexSessionNavigator(),
        debugLogger: CodexHookDebugLogger = .disabled,
        launchedAt: Date = Date(),
        autoDenyLeadTime: TimeInterval = 1
    ) {
        self.persistence = persistence
        self.threadNameStore = threadNameStore
        self.sessionNavigator = sessionNavigator
        self.debugLogger = debugLogger
        self.launchedAt = launchedAt
        self.autoDenyLeadTime = autoDenyLeadTime
    }

    deinit {
        approvalTimeoutTasks.values.forEach { $0.cancel() }
        suspiciousSessionTasks.values.forEach { $0.cancel() }
    }

    func updateHookSettings(_ config: SettingsConfig) {
        preToolUseTimeout = TimeInterval(max(1, config.preToolUseTimeout))
        suspiciousSessionTimeout = TimeInterval(max(1, config.suspiciousSessionTimeout))
        showSessionEndNotifications = config.showSessionEndNotifications
        rescheduleSuspiciousSessionTracking()
    }

    func handleIncomingPayload(_ data: Data, client: Int32) -> CodexHookRelayServer.PayloadDisposition {
        let pendingApproval = PendingApproval.decode(from: data)
        if let pendingApproval {
            beginApprovalCycleIfNeeded(with: pendingApproval.key)
        }

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
        scheduleApprovalTimeout(for: pendingApproval.key)
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

    @discardableResult
    func openSession(_ session: CodexSessionGroup) -> Bool {
        sessionNavigator.open(session)
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

        approvalDecisionCounts.record(status: approvalStatus)
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

        approvalDecisionCounts.record(status: approvalStatus)
        removeResolvedToolCall(withID: toolCall.id, approvalKey: toolCall.id)
    }

    private func upsert(session: CodexRecentSession, pendingApprovalKey: String? = nil) {
        guard session.updatedAt >= launchedAt else {
            return
        }

        let previous = sessionIndex[session.id]
        if let existing = sessionIndex[session.id] {
            sessionIndex[session.id] = CodexSessionProjection.merge(existing: existing, update: session)
        } else {
            sessionIndex[session.id] = session
        }
        upsertSessionSummaryActivity(from: session)

        if let pendingApprovalKey, !approvalQueue.contains(pendingApprovalKey) {
            approvalQueue.append(pendingApprovalKey)
        }

        syncApprovalTracking(for: session)
        syncSuspiciousSessionTracking(for: sessionIndex[session.sessionID] ?? sessionIndex[session.id] ?? session)
        publishSessionEndedNotificationIfNeeded(previous: previous, current: sessionIndex[session.id] ?? session)

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
        let threadMetadata = threadNameStore.threadMetadataBySessionID()

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
                title: sessionTitle(for: base, threadName: threadMetadata[sessionID]?.title),
                projectName: base.projectName,
                updatedAt: max(base.updatedAt, toolCalls.map(\.updatedAt).max() ?? base.updatedAt),
                state: base.state,
                source: threadMetadata[sessionID]?.source,
                rolloutPath: threadMetadata[sessionID]?.rolloutPath,
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
        case .suspicious:
            return 1
        case .idle:
            return 2
        case .completed:
            return 3
        case .unknown:
            return 4
        }
    }

    private func publishVisibleSessions() {
        while let firstKey = approvalQueue.first, shouldDropApprovalTracking(forKey: firstKey) {
            approvalQueue.removeFirst()
        }

        let visibleToolID = approvalQueue.first
        let allGroups = allSessionGroups(from: sessionIndex.values)
        runningSessionCount = allGroups.filter { $0.state == .running || $0.state == .suspicious }.count
        pendingApprovalToolCall = allGroups
            .flatMap(\.toolCalls)
            .first(where: { $0.id == visibleToolID })

        sessions = sortedSessionGroups(allGroups)
            .prefix(12)
            .map { group in
                CodexSessionGroup(
                    id: group.id,
                    title: group.title,
                    projectName: group.projectName,
                    updatedAt: group.updatedAt,
                    state: group.state,
                    source: group.source,
                    rolloutPath: group.rolloutPath,
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

    var hasPendingApprovals: Bool {
        pendingApprovalToolCall != nil
    }

    private func beginApprovalCycleIfNeeded(with key: String) {
        guard approvalQueue.isEmpty, pendingApprovalClients[key] == nil else {
            return
        }

        approvalDecisionCounts = ApprovalDecisionCounts()
    }

    private func publishSessionEndedNotificationIfNeeded(previous: CodexRecentSession?, current: CodexRecentSession) {
        guard showSessionEndNotifications else { return }
        guard current.toolUseID == nil else { return }
        guard current.state == .completed else { return }
        guard previous?.state != .completed else { return }

        sessionEndedNotification = SessionEndedNotification(
            id: UUID(),
            sessionID: current.sessionID,
            title: sessionTitle(for: current, threadName: threadNameStore.threadNamesBySessionID()[current.sessionID]),
            projectName: current.projectName
        )
    }

    private func removeResolvedToolCall(withID id: String, approvalKey: String) {
        sessionIndex.removeValue(forKey: id)
        pendingApprovalClients.removeValue(forKey: approvalKey)
        approvalQueue.removeAll { $0 == approvalKey }
        approvalTimeoutTasks.removeValue(forKey: approvalKey)?.cancel()
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
        approvalTimeoutTasks.removeValue(forKey: approvalKey)?.cancel()
    }

    private func shouldDropApprovalTracking(forKey key: String) -> Bool {
        guard let session = sessionIndex[key] else {
            pendingApprovalClients.removeValue(forKey: key)
            approvalTimeoutTasks.removeValue(forKey: key)?.cancel()
            return true
        }

        guard session.requiresApproval else {
            pendingApprovalClients.removeValue(forKey: key)
            approvalTimeoutTasks.removeValue(forKey: key)?.cancel()
            return true
        }

        return false
    }

    private func upsertSessionSummaryActivity(from session: CodexRecentSession) {
        guard session.toolUseID != nil else {
            return
        }

        let summaryID = session.sessionID
        let existing = sessionIndex[summaryID]
        let nextState: CodexSessionState = session.state == .completed ? .completed : .running

        sessionIndex[summaryID] = CodexRecentSession(
            id: summaryID,
            sessionID: session.sessionID,
            projectName: session.projectName,
            updatedAt: session.updatedAt,
            state: nextState,
            cwd: session.cwd,
            model: session.model == "unknown" ? (existing?.model ?? session.model) : session.model,
            transcriptPath: session.transcriptPath ?? existing?.transcriptPath,
            lastEvent: session.lastEvent,
            lastUserPrompt: existing?.lastUserPrompt,
            lastAssistantMessage: existing?.lastAssistantMessage,
            toolName: nil,
            toolUseID: nil,
            toolCommand: nil,
            requiresApproval: false,
            approvalStatus: nil
        )
    }

    private func syncSuspiciousSessionTracking(for session: CodexRecentSession) {
        guard session.toolUseID == nil else {
            return
        }

        let sessionID = session.sessionID
        guard session.state != .completed else {
            suspiciousSessionTasks.removeValue(forKey: sessionID)?.cancel()
            return
        }

        suspiciousSessionTasks.removeValue(forKey: sessionID)?.cancel()
        suspiciousSessionTasks[sessionID] = Task { [weak self] in
            guard let self else { return }
            let duration = UInt64(max(0.1, self.suspiciousSessionTimeout) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: duration)
            guard !Task.isCancelled else {
                return
            }

            await self.markSessionSuspiciousIfNeeded(sessionID: sessionID)
        }
    }

    private func rescheduleSuspiciousSessionTracking() {
        let activeSessionIDs = Set(sessionIndex.values.compactMap { session in
            guard session.toolUseID == nil, session.state != .completed else {
                return nil
            }
            return session.sessionID
        })

        for sessionID in suspiciousSessionTasks.keys where !activeSessionIDs.contains(sessionID) {
            suspiciousSessionTasks.removeValue(forKey: sessionID)?.cancel()
        }

        for session in sessionIndex.values where session.toolUseID == nil && session.state != .completed {
            syncSuspiciousSessionTracking(for: session)
        }
    }

    private func markSessionSuspiciousIfNeeded(sessionID: String) {
        suspiciousSessionTasks.removeValue(forKey: sessionID)?.cancel()

        guard let session = sessionIndex[sessionID], session.toolUseID == nil else {
            return
        }

        guard session.state == .running else {
            return
        }

        sessionIndex[sessionID] = CodexRecentSession(
            id: session.id,
            sessionID: session.sessionID,
            projectName: session.projectName,
            updatedAt: session.updatedAt,
            state: .suspicious,
            cwd: session.cwd,
            model: session.model,
            transcriptPath: session.transcriptPath,
            lastEvent: session.lastEvent,
            lastUserPrompt: session.lastUserPrompt,
            lastAssistantMessage: session.lastAssistantMessage,
            toolName: session.toolName,
            toolUseID: session.toolUseID,
            toolCommand: session.toolCommand,
            requiresApproval: session.requiresApproval,
            approvalStatus: session.approvalStatus
        )
        suspiciousSessionNotification = SuspiciousSessionNotification(
            id: UUID(),
            sessionID: session.sessionID,
            title: sessionTitle(for: session, threadName: threadNameStore.threadNamesBySessionID()[session.sessionID]),
            projectName: session.projectName
        )
        publishVisibleSessions()
    }

    private func scheduleApprovalTimeout(for key: String) {
        approvalTimeoutTasks.removeValue(forKey: key)?.cancel()

        let effectiveDelay = max(0.1, preToolUseTimeout - autoDenyLeadTime)
        approvalTimeoutTasks[key] = Task { [weak self] in
            let duration = UInt64(effectiveDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: duration)
            guard !Task.isCancelled else {
                return
            }

            await self?.autoDenyPendingApproval(forKey: key)
        }
    }

    private func autoDenyPendingApproval(forKey key: String) {
        guard
            let session = sessionIndex[key],
            session.requiresApproval,
            pendingApprovalClients[key] != nil
        else {
            approvalTimeoutTasks.removeValue(forKey: key)?.cancel()
            return
        }

        debugLogger.log("auto denying pending approval for \(key) before timeout")
        resolve(
            session,
            relayResponse: .deny(
                CodexHookResponse.denyToolUse(reason: "Timed out waiting for approval from CodexIsland")
            ),
            approvalStatus: "timed_out"
        )
    }

    private func sessionTitle(for session: CodexRecentSession, threadName: String?) -> String {
        if let threadName, !threadName.isEmpty {
            return threadName
        }

        return session.projectName
    }
}

struct ApprovalDecisionCounts: Equatable {
    var approved: Int = 0
    var denied: Int = 0

    mutating func record(status: String) {
        switch status {
        case "approved":
            approved += 1
        case "denied":
            denied += 1
        default:
            break
        }
    }
}

struct SessionEndedNotification: Equatable, Identifiable {
    let id: UUID
    let sessionID: String
    let title: String
    let projectName: String
}

struct SuspiciousSessionNotification: Equatable, Identifiable {
    let id: UUID
    let sessionID: String
    let title: String
    let projectName: String
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
            case .preToolUse(let context) = invocation,
            CodexCommandApprovalMatcher.requiresApproval(for: context)
        else {
            return nil
        }

        return PendingApproval(sessionID: context.sessionID, toolUseID: context.toolUseID)
    }
}
