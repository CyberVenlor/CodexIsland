import Darwin
import Combine
import Foundation

@MainActor
final class CodexSessionController: ObservableObject {
    @Published private(set) var sessions: [CodexRecentSession] = []

    private let persistence: CodexSessionPersisting
    private let debugLogger: CodexHookDebugLogger
    private let launchedAt: Date
    private var pendingApprovalClients: [String: Int32] = [:]
    private var sessionIndex: [String: CodexRecentSession] = [:]

    init(
        persistence: CodexSessionPersisting = NoOpCodexSessionPersistence(),
        debugLogger: CodexHookDebugLogger = .disabled,
        launchedAt: Date = Date()
    ) {
        self.persistence = persistence
        self.debugLogger = debugLogger
        self.launchedAt = launchedAt
    }

    func handleIncomingPayload(_ data: Data, client: Int32) -> CodexHookRelayServer.PayloadDisposition {
        if let session = CodexSessionProjection.session(from: data) {
            upsert(session: session)
        } else {
            debugLogger.log("failed to project incoming payload into session")
        }

        do {
            try persistence.recordPayloadData(data)
        } catch {
            debugLogger.log("failed to record incoming payload: \(error.localizedDescription)")
        }

        guard let pendingApproval = PendingApproval.decode(from: data) else {
            return .closeClient
        }

        pendingApprovalClients[pendingApproval.key] = client
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
                try persistence.updateApproval(sessionID: session.id, toolUseID: toolUseID, status: approvalStatus)
            } catch {
                debugLogger.log("failed to persist approval status for \(key): \(error.localizedDescription)")
            }

            if let existing = sessionIndex[session.id] {
                upsert(session: CodexSessionProjection.approvalUpdated(existing, status: approvalStatus))
            }
        }
    }

    private func upsert(session: CodexRecentSession) {
        guard session.updatedAt >= launchedAt else {
            return
        }

        if let existing = sessionIndex[session.id] {
            sessionIndex[session.id] = CodexSessionProjection.merge(existing: existing, update: session)
        } else {
            sessionIndex[session.id] = session
        }

        sessions = sessionIndex.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(12)
            .map { $0 }
    }

    private func approvalKey(for session: CodexRecentSession) -> String? {
        guard let toolUseID = session.toolUseID else {
            return nil
        }

        return "\(session.id)::\(toolUseID)"
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
