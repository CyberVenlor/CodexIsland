import Foundation

final class CodexHookRegistry {
    typealias SessionStartHandler = (CodexSessionStartContext) throws -> CodexHookResponse?
    typealias SessionEndHandler = (CodexStopContext) throws -> CodexHookResponse?
    typealias PreToolUseHandler = (CodexPreToolUseContext) throws -> CodexHookResponse?
    typealias PostToolUseHandler = (CodexPostToolUseContext) throws -> CodexHookResponse?

    private var sessionStartHandlers: [SessionStartHandler] = []
    private var sessionEndHandlers: [SessionEndHandler] = []
    private var preToolUseHandlers: [PreToolUseHandler] = []
    private var postToolUseHandlers: [PostToolUseHandler] = []
    private let sessionStore: CodexSessionStore?
    private let debugLogger: CodexHookDebugLogger

    init(
        sessionStore: CodexSessionStore? = CodexSessionStore(),
        debugLogger: CodexHookDebugLogger = CodexHookDebugLogger()
    ) {
        self.sessionStore = sessionStore
        self.debugLogger = debugLogger
    }

    @discardableResult
    func onSessionStart(_ handler: @escaping SessionStartHandler) -> Self {
        sessionStartHandlers.append(handler)
        return self
    }

    // Session end is backed by Codex's Stop hook.
    @discardableResult
    func onSessionEnd(_ handler: @escaping SessionEndHandler) -> Self {
        sessionEndHandlers.append(handler)
        return self
    }

    @discardableResult
    func onPreToolUse(_ handler: @escaping PreToolUseHandler) -> Self {
        preToolUseHandlers.append(handler)
        return self
    }

    @discardableResult
    func onPostToolUse(_ handler: @escaping PostToolUseHandler) -> Self {
        postToolUseHandlers.append(handler)
        return self
    }

    func handle(_ invocation: CodexHookInvocation) throws -> CodexHookResponse? {
        switch invocation {
        case .sessionStart(let context):
            return try reduceResponses(from: sessionStartHandlers, with: context)
        case .preToolUse(let context):
            return try reduceResponses(from: preToolUseHandlers, with: context)
        case .postToolUse(let context):
            return try reduceResponses(from: postToolUseHandlers, with: context)
        case .stop(let context):
            return try reduceResponses(from: sessionEndHandlers, with: context)
        }
    }

    func handle(input data: Data) throws -> CodexHookResponse? {
        debugLogger.log("handle(input:) received \(data.count) bytes")

        do {
            let invocation = try CodexHookInvocation.decode(from: data)
            debugLogger.log("decoded hook event \(invocation.hookEventName.rawValue)")

            do {
                try sessionStore?.record(invocation)
                debugLogger.log("recorded session for \(invocation.hookEventName.rawValue)")
            } catch {
                debugLogger.log("failed to record session: \(error.localizedDescription)")
                throw error
            }

            let response = try handle(invocation)
            debugLogger.log("handler completed for \(invocation.hookEventName.rawValue); response=\(response == nil ? "nil" : "present")")
            return response
        } catch {
            debugLogger.log("handle(input:) failed: \(error.localizedDescription)")
            throw error
        }
    }

    func encodedResponse(for data: Data, using encoder: JSONEncoder = JSONEncoder()) throws -> Data? {
        guard let response = try handle(input: data) else {
            return nil
        }

        return try encoder.encode(response)
    }

    func run(
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        debugLogger.log("run() started")
        let inputData = try input.readToEnd() ?? Data()
        debugLogger.log("run() read \(inputData.count) bytes from stdin")

        guard !inputData.isEmpty else {
            debugLogger.log("run() exiting early because stdin was empty")
            return
        }

        if let response = try encodedResponse(for: inputData, using: encoder) {
            output.write(response)
            debugLogger.log("run() wrote \(response.count) response bytes to stdout")
        } else {
            debugLogger.log("run() produced no response")
        }
    }

    private func reduceResponses<Context>(
        from handlers: [(Context) throws -> CodexHookResponse?],
        with context: Context
    ) throws -> CodexHookResponse? {
        var combined: CodexHookResponse?

        for handler in handlers {
            guard let response = try handler(context) else {
                continue
            }

            combined = combined?.merging(response) ?? response
        }

        return combined
    }
}

struct CodexHookDebugLogger {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let fileManager: FileManager
    private let logURL: URL

    init(
        logURL: URL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("codex-island-hook-debug.log"),
        fileManager: FileManager = .default
    ) {
        self.logURL = logURL
        self.fileManager = fileManager
    }

    func log(_ message: String) {
        let timestamp = Self.formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        do {
            try fileManager.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )

            if fileManager.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } else {
                try line.write(to: logURL, atomically: true, encoding: .utf8)
            }
        } catch {
        }
    }
}
