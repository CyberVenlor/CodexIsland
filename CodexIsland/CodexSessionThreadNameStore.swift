import Foundation
import SQLite3

struct CodexSessionThreadNameStore {
    private let fileManager: FileManager
    private let databaseURL: URL
    private let indexURL: URL

    init(
        databaseURL: URL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("state_5.sqlite"),
        indexURL: URL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("session_index.jsonl"),
        fileManager: FileManager = .default
    ) {
        self.databaseURL = databaseURL
        self.indexURL = indexURL
        self.fileManager = fileManager
    }

    func threadNamesBySessionID() -> [String: String] {
        var names = loadThreadNamesFromSQLite()

        for (id, name) in loadThreadNamesFromIndex() where names[id] == nil {
            names[id] = name
        }

        return names
    }

    private func loadThreadNamesFromSQLite() -> [String: String] {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return [:]
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return [:]
        }
        defer { sqlite3_close(database) }

        let query = "SELECT id, title FROM threads WHERE archived = 0;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            return [:]
        }
        defer { sqlite3_finalize(statement) }

        var result: [String: String] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idPointer = sqlite3_column_text(statement, 0),
                let titlePointer = sqlite3_column_text(statement, 1)
            else {
                continue
            }

            let id = String(cString: idPointer).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = String(cString: titlePointer).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !id.isEmpty, !title.isEmpty else {
                continue
            }

            result[id] = title
        }

        return result
    }

    private func loadThreadNamesFromIndex() -> [String: String] {
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
