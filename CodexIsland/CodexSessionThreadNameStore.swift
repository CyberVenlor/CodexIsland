import Foundation

struct CodexSessionThreadNameStore {
    private let fileManager: FileManager
    private let indexURL: URL

    init(
        indexURL: URL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("session_index.jsonl"),
        fileManager: FileManager = .default
    ) {
        self.indexURL = indexURL
        self.fileManager = fileManager
    }

    func threadNamesBySessionID() -> [String: String] {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return [:]
        }

        guard let data = try? Data(contentsOf: indexURL), !data.isEmpty else {
            return [:]
        }

        guard let content = String(data: data, encoding: .utf8) else {
            return [:]
        }

        return content
            .split(whereSeparator: \.isNewline)
            .reduce(into: [:]) { result, line in
                guard
                    let data = line.data(using: .utf8),
                    let entry = try? JSONDecoder().decode(CodexSessionThreadNameEntry.self, from: data),
                    !entry.id.isEmpty,
                    let threadName = entry.threadName?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !threadName.isEmpty
                else {
                    return
                }

                result[entry.id] = threadName
            }
    }
}

private struct CodexSessionThreadNameEntry: Decodable {
    let id: String
    let threadName: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
    }
}
