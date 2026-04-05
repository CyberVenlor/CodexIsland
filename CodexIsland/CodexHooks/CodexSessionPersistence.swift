import Foundation

protocol CodexSessionPersisting {
    func recentSessions(limit: Int) throws -> [CodexRecentSession]
    func record(_ invocation: CodexHookInvocation) throws
    func recordPayloadData(_ data: Data) throws
    func updateApproval(sessionID: String, toolUseID: String, status: String) throws
}

struct NoOpCodexSessionPersistence: CodexSessionPersisting {
    func recentSessions(limit: Int) throws -> [CodexRecentSession] { [] }
    func record(_ invocation: CodexHookInvocation) throws {}
    func recordPayloadData(_ data: Data) throws {}
    func updateApproval(sessionID: String, toolUseID: String, status: String) throws {}
}
