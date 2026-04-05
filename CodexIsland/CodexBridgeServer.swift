import Foundation
import SwiftUI

@MainActor
final class CodexBridgeServer: ObservableObject {
    @Published private(set) var sessions: [CodexRecentSession] = []

    private let debugLogger: CodexHookDebugLogger
    private let socketPath: String
    private let acceptQueue = DispatchQueue(label: "CodexIsland.bridge.accept", qos: .userInitiated)
    private let readQueue = DispatchQueue(label: "CodexIsland.bridge.read", qos: .userInitiated)
    private var listenSocket: Int32 = -1
    private var pendingApprovalClients: [String: Int32] = [:]
    private var sessionIndex: [String: CodexRecentSession] = [:]

    init(
        debugLogger: CodexHookDebugLogger = CodexHookDebugLogger(),
        socketPath: String = "/tmp/vibe-island.sock"
    ) {
        self.debugLogger = debugLogger
        self.socketPath = socketPath
    }

    func start() {
        startSocketServer()
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
        recordIncomingPayload(data)

        if let payload = decodedPayload, payload.requiresApproval, let key = approvalKey(for: payload) {
            pendingApprovalClients[key] = client
            debugLogger.log("stored pending approval client for \(key)")
        } else {
            close(client)
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
            updateApproval(sessionID: session.id, toolUseID: toolUseID, status: status)
        }
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

    private func recordIncomingPayload(_ data: Data) {
        if let invocation = try? JSONDecoder().decode(CodexHookEventEnvelopeProxy.self, from: data).decodeInvocation(from: data) {
            upsert(session: makeSession(from: invocation))
            return
        }

        if let payload = try? JSONDecoder().decode(IncomingBridgePayload.self, from: data) {
            upsert(session: makeSession(from: payload))
            return
        }

        debugLogger.log("failed to decode socket payload into session")
    }

    private func updateApproval(sessionID: String, toolUseID: String, status: String) {
        guard var session = sessionIndex[sessionID], session.toolUseID == toolUseID else {
            debugLogger.log("no in-memory session for approval update \(sessionID)::\(toolUseID)")
            return
        }

        session = CodexRecentSession(
            id: session.id,
            title: session.title,
            updatedAt: Date(),
            state: session.state,
            cwd: session.cwd,
            model: session.model,
            transcriptPath: session.transcriptPath,
            lastEvent: session.lastEvent,
            lastAssistantMessage: session.lastAssistantMessage,
            toolName: session.toolName,
            toolUseID: session.toolUseID,
            toolCommand: session.toolCommand,
            requiresApproval: false,
            approvalStatus: status
        )
        upsert(session: session)
    }

    private func upsert(session: CodexRecentSession) {
        if let existing = sessionIndex[session.id] {
            sessionIndex[session.id] = merge(existing: existing, update: session)
        } else {
            sessionIndex[session.id] = session
        }

        sessions = sessionIndex.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(12)
            .map { $0 }
    }

    private func merge(existing: CodexRecentSession, update: CodexRecentSession) -> CodexRecentSession {
        CodexRecentSession(
            id: existing.id,
            title: update.title,
            updatedAt: update.updatedAt,
            state: update.state,
            cwd: update.cwd,
            model: update.model == "unknown" ? existing.model : update.model,
            transcriptPath: update.transcriptPath ?? existing.transcriptPath,
            lastEvent: update.lastEvent,
            lastAssistantMessage: update.lastAssistantMessage ?? existing.lastAssistantMessage,
            toolName: update.toolName ?? existing.toolName,
            toolUseID: update.toolUseID ?? existing.toolUseID,
            toolCommand: update.toolCommand ?? existing.toolCommand,
            requiresApproval: update.requiresApproval,
            approvalStatus: update.approvalStatus ?? existing.approvalStatus
        )
    }

    private func makeSession(from invocation: CodexHookInvocation) -> CodexRecentSession {
        switch invocation {
        case .sessionStart(let context):
            return CodexRecentSession(
                id: context.sessionID,
                title: makeTitle(from: context.cwd),
                updatedAt: Date(),
                state: .running,
                cwd: context.cwd,
                model: context.model,
                transcriptPath: context.transcriptPath,
                lastEvent: context.hookEventName.rawValue,
                lastAssistantMessage: nil,
                toolName: nil,
                toolUseID: nil,
                toolCommand: nil,
                requiresApproval: false,
                approvalStatus: nil
            )
        case .preToolUse(let context):
            return CodexRecentSession(
                id: context.sessionID,
                title: makeTitle(from: context.cwd),
                updatedAt: Date(),
                state: .running,
                cwd: context.cwd,
                model: context.model,
                transcriptPath: context.transcriptPath,
                lastEvent: context.hookEventName.rawValue,
                lastAssistantMessage: nil,
                toolName: context.toolName.displayName,
                toolUseID: context.toolUseID,
                toolCommand: context.toolInput.command,
                requiresApproval: true,
                approvalStatus: "pending"
            )
        case .postToolUse(let context):
            return CodexRecentSession(
                id: context.sessionID,
                title: makeTitle(from: context.cwd),
                updatedAt: Date(),
                state: .running,
                cwd: context.cwd,
                model: context.model,
                transcriptPath: context.transcriptPath,
                lastEvent: context.hookEventName.rawValue,
                lastAssistantMessage: nil,
                toolName: context.toolName.displayName,
                toolUseID: context.toolUseID,
                toolCommand: context.toolInput.command,
                requiresApproval: false,
                approvalStatus: nil
            )
        case .stop(let context):
            return CodexRecentSession(
                id: context.sessionID,
                title: makeTitle(from: context.cwd),
                updatedAt: Date(),
                state: context.stopHookActive ? .running : .completed,
                cwd: context.cwd,
                model: context.model,
                transcriptPath: context.transcriptPath,
                lastEvent: context.hookEventName.rawValue,
                lastAssistantMessage: context.lastAssistantMessage,
                toolName: nil,
                toolUseID: nil,
                toolCommand: nil,
                requiresApproval: false,
                approvalStatus: nil
            )
        }
    }

    private func makeSession(from payload: IncomingBridgePayload) -> CodexRecentSession {
        let eventName = payload.event ?? payload.codexEventType
        return CodexRecentSession(
            id: payload.sessionID ?? UUID().uuidString,
            title: makeTitle(from: payload.cwd ?? payload.transcriptPath ?? "unknown"),
            updatedAt: Date(),
            state: state(for: payload),
            cwd: payload.cwd ?? payload.transcriptPath ?? "unknown",
            model: payload.model ?? "unknown",
            transcriptPath: payload.transcriptPath,
            lastEvent: eventName,
            lastAssistantMessage: payload.lastAssistantMessage,
            toolName: payload.toolName,
            toolUseID: payload.toolUseID,
            toolCommand: payload.toolCommand ?? payload.toolInput?.command,
            requiresApproval: payload.requiresApproval,
            approvalStatus: payload.requiresApproval ? "pending" : payload.permissionStatus
        )
    }

    private func state(for payload: IncomingBridgePayload) -> CodexSessionState {
        let eventName = (payload.event ?? payload.codexEventType ?? "").lowercased()
        if eventName == "stop" || eventName == "hook-stop" || eventName == "hook-session-stop" {
            return payload.stopHookActive == true ? .running : .completed
        }
        return .running
    }

    private func makeTitle(from path: String) -> String {
        let component = URL(fileURLWithPath: path).lastPathComponent
        return component.isEmpty ? path : component
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
    let cwd: String?
    let model: String?
    let transcriptPath: String?
    let toolUseID: String?
    let stopHookActive: Bool?
    let lastAssistantMessage: String?
    let toolName: String?
    let toolInput: BridgeToolInput?
    let toolCommand: String?
    let codexEventType: String?
    let codexPermissionMode: String?
    let permissionStatus: String?

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
        case cwd
        case model
        case transcriptPath = "transcript_path"
        case toolUseID = "tool_use_id"
        case stopHookActive = "stop_hook_active"
        case lastAssistantMessage = "last_assistant_message"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolCommand = "tool_command"
        case codexEventType = "codex_event_type"
        case codexPermissionMode = "codex_permission_mode"
        case permissionStatus = "permission_status"
    }
}

private struct BridgeToolInput: Decodable {
    let command: String?
}

private struct CodexHookEventEnvelopeProxy: Decodable {
    let hookEventName: CodexHookEventName

    private enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
    }

    func decodeInvocation(from data: Data) throws -> CodexHookInvocation {
        let decoder = JSONDecoder()

        switch hookEventName {
        case .sessionStart:
            return .sessionStart(try decoder.decode(CodexSessionStartContext.self, from: data))
        case .preToolUse:
            return .preToolUse(try decoder.decode(CodexPreToolUseContext.self, from: data))
        case .postToolUse:
            return .postToolUse(try decoder.decode(CodexPostToolUseContext.self, from: data))
        case .stop:
            return .stop(try decoder.decode(CodexStopContext.self, from: data))
        }
    }
}

private extension CodexToolName {
    var displayName: String {
        switch self {
        case .bash:
            return "Bash"
        case .other(let value):
            return value
        }
    }
}
