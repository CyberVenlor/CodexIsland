import Darwin
import Combine
import Foundation

@MainActor
final class CodexSessionController: ObservableObject {
    @Published private(set) var sessions: [CodexRecentSession] = []

    private let sessionStore: CodexSessionStore
    private let debugLogger: CodexHookDebugLogger
    private var pendingApprovalClients: [String: Int32] = [:]

    init(
        sessionStore: CodexSessionStore = CodexSessionStore(),
        debugLogger: CodexHookDebugLogger = CodexHookDebugLogger()
    ) {
        self.sessionStore = sessionStore
        self.debugLogger = debugLogger
        reloadSessions()
    }

    func handleIncomingPayload(_ data: Data, client: Int32) -> CodexHookRelayServer.PayloadDisposition {
        do {
            try sessionStore.recordPayloadData(data)
            reloadSessions()
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
        resolve(session, response: nil, approvalStatus: "approved")
    }

    func deny(_ session: CodexRecentSession) {
        do {
            let response = try JSONEncoder().encode(
                CodexHookResponse.denyToolUse(reason: "Denied from CodexIsland")
            )
            resolve(session, response: response, approvalStatus: "denied")
        } catch {
            debugLogger.log("failed to encode deny response for \(session.id): \(error.localizedDescription)")
        }
    }

    private func resolve(_ session: CodexRecentSession, response: Data?, approvalStatus: String) {
        guard
            let key = approvalKey(for: session),
            let client = pendingApprovalClients.removeValue(forKey: key)
        else {
            debugLogger.log("no pending approval client for session \(session.id)")
            return
        }

        if let response {
            do {
                try FileHandle(fileDescriptor: client, closeOnDealloc: false).write(contentsOf: response)
                debugLogger.log("wrote deny response for \(key)")
            } catch {
                debugLogger.log("failed to write response for \(key): \(error.localizedDescription)")
            }
        } else {
            debugLogger.log("approved tool use for \(key) without emitting hook output")
        }

        close(client)

        if let toolUseID = session.toolUseID {
            do {
                try sessionStore.updateApproval(sessionID: session.id, toolUseID: toolUseID, status: approvalStatus)
                reloadSessions()
            } catch {
                debugLogger.log("failed to persist approval status for \(key): \(error.localizedDescription)")
            }
        }
    }

    private func reloadSessions() {
        do {
            sessions = try sessionStore.recentSessions(limit: 12)
        } catch {
            debugLogger.log("failed to reload sessions: \(error.localizedDescription)")
        }
    }

    private func approvalKey(for session: CodexRecentSession) -> String? {
        guard let toolUseID = session.toolUseID else {
            return nil
        }

        return "\(session.id)::\(toolUseID)"
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
