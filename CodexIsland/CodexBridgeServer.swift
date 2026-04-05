import Foundation
import SwiftUI

@MainActor
final class CodexBridgeServer: ObservableObject {
    @Published private(set) var sessions: [CodexRecentSession] = []
    @Published private(set) var loadError: String?

    private let sessionStore: CodexSessionStore
    private let debugLogger: CodexHookDebugLogger
    private let socketPath: String
    private let acceptQueue = DispatchQueue(label: "CodexIsland.bridge.accept", qos: .userInitiated)
    private let readQueue = DispatchQueue(label: "CodexIsland.bridge.read", qos: .userInitiated)
    private var listenSocket: Int32 = -1
    private var pendingApprovalClients: [String: Int32] = [:]

    init(
        sessionStore: CodexSessionStore = CodexSessionStore(),
        debugLogger: CodexHookDebugLogger = CodexHookDebugLogger(),
        socketPath: String = "/tmp/vibe-island.sock"
    ) {
        self.sessionStore = sessionStore
        self.debugLogger = debugLogger
        self.socketPath = socketPath
    }

    func start() {
        loadSessions()
        startSocketServer()
    }

    func loadSessions() {
        do {
            sessions = try sessionStore.recentSessions(limit: 12)
            loadError = nil
        } catch {
            sessions = []
            loadError = error.localizedDescription
            debugLogger.log("failed to load sessions in app: \(error.localizedDescription)")
        }
    }

    func approve(_ session: CodexRecentSession) {
        respond(to: session, with: .approveToolUse())
    }

    func deny(_ session: CodexRecentSession) {
        respond(to: session, with: .denyToolUse(reason: "Denied from Vibe Island"))
    }

    deinit {
        if listenSocket >= 0 {
            close(listenSocket)
        }

        unlink(socketPath)
    }

    private func startSocketServer() {
        guard listenSocket < 0 else {
            return
        }

        unlink(socketPath)

        let socketFD = socket(AF_UNIX, Int32(SOCK_STREAM), 0)
        guard socketFD >= 0 else {
            debugLogger.log("failed to create UNIX socket for \(socketPath)")
            return
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        let bytes = Array(socketPath.utf8)
        guard bytes.count < maxLength else {
            debugLogger.log("socket path too long: \(socketPath)")
            close(socketFD)
            return
        }

        withUnsafeMutablePointer(to: &address.sun_path) { pathPointer in
            pathPointer.withMemoryRebound(to: CChar.self, capacity: maxLength) { pointer in
                pointer.initialize(repeating: 0, count: maxLength)
                for (index, byte) in bytes.enumerated() {
                    pointer[index] = CChar(bitPattern: byte)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            debugLogger.log("failed to bind UNIX socket at \(socketPath)")
            close(socketFD)
            return
        }

        chmod(socketPath, 0o666)

        guard listen(socketFD, SOMAXCONN) == 0 else {
            debugLogger.log("failed to listen on UNIX socket at \(socketPath)")
            close(socketFD)
            unlink(socketPath)
            return
        }

        listenSocket = socketFD
        debugLogger.log("started UNIX socket listener at \(socketPath)")

        acceptQueue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    private func acceptLoop() {
        while listenSocket >= 0 {
            let client = accept(listenSocket, nil, nil)

            if client < 0 {
                debugLogger.log("accept failed on \(socketPath)")
                continue
            }

            debugLogger.log("accepted socket client on \(socketPath)")
            readQueue.async { [weak self] in
                self?.handleClient(client)
            }
        }
    }

    private func handleClient(_ client: Int32) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(client, &buffer, buffer.count)

        if count < 0 {
            debugLogger.log("read failed on socket client")
            close(client)
            return
        }

        if count > 0 {
            data.append(contentsOf: buffer.prefix(count))
        }

        guard !data.isEmpty else {
            debugLogger.log("received empty payload from socket client")
            close(client)
            return
        }

        debugLogger.log("received \(data.count) bytes from socket client")

        let decodedPayload = decodeIncomingPayload(data)

        do {
            try sessionStore.recordPayloadData(data)
        } catch {
            debugLogger.log("failed to record socket payload: \(error.localizedDescription)")
        }

        if let payload = decodedPayload, payload.requiresApproval, let key = approvalKey(for: payload) {
            pendingApprovalClients[key] = client
            debugLogger.log("stored pending approval client for \(key)")
        } else {
            close(client)
        }

        Task { @MainActor [weak self] in
            self?.loadSessions()
        }
    }

    private func respond(to session: CodexRecentSession, with response: CodexHookResponse) {
        guard let key = approvalKey(for: session), let client = pendingApprovalClients.removeValue(forKey: key) else {
            debugLogger.log("no pending approval client for session \(session.id)")
            return
        }

        do {
            let data = try JSONEncoder().encode(response)
            try FileHandle(fileDescriptor: client, closeOnDealloc: false).write(contentsOf: data)
            debugLogger.log("wrote approval response for \(key)")
        } catch {
            debugLogger.log("failed to write approval response for \(key): \(error.localizedDescription)")
        }

        close(client)

        if let toolUseID = session.toolUseID {
            let status = response.hookSpecificOutput?.permissionDecision?.rawValue ?? "resolved"
            do {
                try sessionStore.updateApproval(sessionID: session.id, toolUseID: toolUseID, status: status)
            } catch {
                debugLogger.log("failed to persist approval status for \(key): \(error.localizedDescription)")
            }
        }

        loadSessions()
    }

    private func decodeIncomingPayload(_ data: Data) -> IncomingPayload? {
        if let preTool = try? JSONDecoder().decode(CodexPreToolUseContext.self, from: data) {
            return IncomingPayload(
                sessionID: preTool.sessionID,
                toolUseID: preTool.toolUseID,
                requiresApproval: true
            )
        }

        if let payload = try? JSONDecoder().decode(IncomingBridgePayload.self, from: data) {
            return IncomingPayload(
                sessionID: payload.sessionID,
                toolUseID: payload.toolUseID,
                requiresApproval: payload.requiresApproval
            )
        }

        return nil
    }

    private func approvalKey(for session: CodexRecentSession) -> String? {
        guard let toolUseID = session.toolUseID else {
            return nil
        }

        return "\(session.id)::\(toolUseID)"
    }

    private func approvalKey(for payload: IncomingPayload) -> String? {
        guard let sessionID = payload.sessionID, let toolUseID = payload.toolUseID else {
            return nil
        }

        return "\(sessionID)::\(toolUseID)"
    }
}

private struct IncomingPayload {
    let sessionID: String?
    let toolUseID: String?
    let requiresApproval: Bool
}

private struct IncomingBridgePayload: Decodable {
    let event: String?
    let sessionID: String?
    let toolUseID: String?
    let codexEventType: String?
    let codexPermissionMode: String?

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
        case toolUseID = "tool_use_id"
        case codexEventType = "codex_event_type"
        case codexPermissionMode = "codex_permission_mode"
    }
}
