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
        defer { close(client) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = read(client, &buffer, buffer.count)

            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
                continue
            }

            if count == 0 {
                break
            }

            debugLogger.log("read failed on socket client")
            return
        }

        guard !data.isEmpty else {
            debugLogger.log("received empty payload from socket client")
            return
        }

        debugLogger.log("received \(data.count) bytes from socket client")

        do {
            try sessionStore.recordPayloadData(data)
        } catch {
            debugLogger.log("failed to record socket payload: \(error.localizedDescription)")
        }

        Task { @MainActor [weak self] in
            self?.loadSessions()
        }
    }
}
