import Foundation

struct CodexCLIConfigStore {
    let fileManager: FileManager
    let configURL: URL

    init(
        fileManager: FileManager = .default,
        configURL: URL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml")
    ) {
        self.fileManager = fileManager
        self.configURL = configURL
    }

    func mergingCLIConfig(into config: SettingsConfig) -> SettingsConfig {
        guard
            fileManager.fileExists(atPath: configURL.path),
            let contents = try? String(contentsOf: configURL, encoding: .utf8)
        else {
            return config
        }

        var merged = config
        let approvalPolicy = value(for: "approval_policy", in: contents)
        let sandboxMode = value(for: "sandbox_mode", in: contents)
        merged.codexExternalApprovalModeEnabled =
            approvalPolicy == "never" && sandboxMode == "danger-full-access"
        return merged
    }

    func write(config: SettingsConfig) throws {
        let fileExists = fileManager.fileExists(atPath: configURL.path)
        let existingContents = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let updatedContents = updatedContents(
            from: existingContents,
            externalApprovalModeEnabled: config.codexExternalApprovalModeEnabled
        )

        if updatedContents.isEmpty {
            if fileExists {
                try? fileManager.removeItem(at: configURL)
            }
            return
        }

        guard fileExists || config.codexExternalApprovalModeEnabled || !existingContents.isEmpty else {
            return
        }

        try fileManager.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try updatedContents.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func updatedContents(from contents: String, externalApprovalModeEnabled: Bool) -> String {
        var updated = contents
        updated = replacingTopLevelValue(for: "approval_policy", in: updated, with: externalApprovalModeEnabled ? "\"never\"" : nil)
        updated = replacingTopLevelValue(for: "sandbox_mode", in: updated, with: externalApprovalModeEnabled ? "\"danger-full-access\"" : nil)

        if externalApprovalModeEnabled {
            updated = insertingTopLevelValueIfNeeded(for: "approval_policy", rawValue: "\"never\"", in: updated)
            updated = insertingTopLevelValueIfNeeded(for: "sandbox_mode", rawValue: "\"danger-full-access\"", in: updated)
        }

        return normalizedTrailingWhitespace(in: updated)
    }

    private func replacingTopLevelValue(for key: String, in contents: String, with rawValue: String?) -> String {
        let lines = contents.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var result: [String] = []
        var insideSection = false

        for line in lines {
            let lineString = String(line)
            let trimmed = lineString.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                insideSection = true
            }

            if !insideSection, isAssignment(for: key, line: lineString) {
                if let rawValue {
                    result.append("\(key) = \(rawValue)")
                }
                continue
            }

            result.append(lineString)
        }

        return result.joined(separator: "\n")
    }

    private func isAssignment(for key: String, line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#") else { return false }
        guard let equalsIndex = trimmed.firstIndex(of: "=") else { return false }
        let candidateKey = trimmed[..<equalsIndex].trimmingCharacters(in: .whitespaces)
        return candidateKey == key
    }

    private func value(for key: String, in contents: String) -> String? {
        let lines = contents.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var insideSection = false

        for line in lines {
            let lineString = String(line)
            let trimmed = lineString.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                insideSection = true
                continue
            }

            guard !insideSection, isAssignment(for: key, line: lineString), let equalsIndex = trimmed.firstIndex(of: "=") else {
                continue
            }

            let rawValue = trimmed[trimmed.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespaces)
            return rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        return nil
    }

    private func insertingTopLevelValueIfNeeded(for key: String, rawValue: String, in contents: String) -> String {
        guard value(for: key, in: contents) == nil else {
            return contents
        }

        let lines = contents.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let assignment = "\(key) = \(rawValue)"

        if let firstSectionIndex = lines.firstIndex(where: isSectionHeader) {
            var updatedLines = lines
            updatedLines.insert(assignment, at: firstSectionIndex)
            return updatedLines.joined(separator: "\n")
        }

        if contents.isEmpty {
            return assignment
        }

        if contents.hasSuffix("\n") {
            return contents + assignment + "\n"
        }

        return contents + "\n" + assignment + "\n"
    }

    private func isSectionHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
    }

    private func normalizedTrailingWhitespace(in contents: String) -> String {
        var result = contents
        while result.hasSuffix("\n\n") {
            result.removeLast()
        }
        return result
    }
}
