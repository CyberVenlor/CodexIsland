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
        try handle(CodexHookInvocation.decode(from: data))
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
        let inputData = try input.readToEnd() ?? Data()

        guard !inputData.isEmpty else {
            return
        }

        if let response = try encodedResponse(for: inputData, using: encoder) {
            output.write(response)
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
