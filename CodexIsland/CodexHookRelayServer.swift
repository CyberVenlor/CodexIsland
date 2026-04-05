import Darwin
import Foundation

enum CodexHookRelayDefaults {
    static let socketPath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".codex", isDirectory: true)
        .appendingPathComponent("codex-island-helper.sock")
        .path
}

final class CodexHookRelayServer {
    enum PayloadDisposition {
        case closeClient
        case holdClient
    }

    typealias PayloadHandler = @MainActor (Data, Int32) -> PayloadDisposition

    private let socketPath: String
    private let debugLogger: CodexHookDebugLogger
    private let payloadHandler: PayloadHandler
    private let acceptQueue = DispatchQueue(label: "CodexIsland.relay.accept", qos: .userInitiated)
    private let readQueue = DispatchQueue(label: "CodexIsland.relay.read", qos: .userInitiated)
    private var listenSocket: Int32 = -1

    init(
        socketPath: String = CodexHookRelayDefaults.socketPath,
        debugLogger: CodexHookDebugLogger = CodexHookDebugLogger(),
        payloadHandler: @escaping PayloadHandler
    ) {
        self.socketPath = socketPath
        self.debugLogger = debugLogger
        self.payloadHandler = payloadHandler
    }

    convenience init(
        sessionController: CodexSessionController,
        socketPath: String = CodexHookRelayDefaults.socketPath,
        debugLogger: CodexHookDebugLogger = CodexHookDebugLogger()
    ) {
        self.init(socketPath: socketPath, debugLogger: debugLogger) { data, client in
            sessionController.handleIncomingPayload(data, client: client)
        }
    }

    func start() {
        startSocketServer()
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

        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: socketPath).deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            debugLogger.log("failed to create socket directory for \(socketPath): \(error.localizedDescription)")
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
        debugLogger.log("started helper relay listener at \(socketPath)")

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

            readQueue.async { [weak self] in
                self?.handleClient(client)
            }
        }
    }

    private func handleClient(_ client: Int32) {
        let data = readPayload(from: client)

        guard !data.isEmpty else {
            debugLogger.log("received empty payload from helper")
            close(client)
            return
        }

        Task { @MainActor [payloadHandler, debugLogger] in
            let disposition = payloadHandler(data, client)
            if disposition == .closeClient {
                close(client)
            } else {
                debugLogger.log("holding client open for manual approval")
            }
        }
    }

    private func readPayload(from client: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = read(client, &buffer, buffer.count)

            if count < 0 {
                debugLogger.log("read failed on socket client")
                return Data()
            }

            if count == 0 {
                break
            }

            data.append(contentsOf: buffer.prefix(count))
        }

        debugLogger.log("received \(data.count) bytes from helper")
        return data
    }
}
