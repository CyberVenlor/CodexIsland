import Foundation

struct CodexHooksConfigStore {
    let fileManager: FileManager
    let hooksURL: URL
    let helperCommand: String

    init(
        fileManager: FileManager = .default,
        hooksURL: URL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json"),
        helperCommand: String = Self.defaultHelperCommand
    ) {
        self.fileManager = fileManager
        self.hooksURL = hooksURL
        self.helperCommand = helperCommand
    }

    func mergingHooksConfig(into config: SettingsConfig) -> SettingsConfig {
        guard
            fileManager.fileExists(atPath: hooksURL.path),
            let data = try? Data(contentsOf: hooksURL),
            let hooksConfig = try? JSONDecoder().decode(CodexHooksFile.self, from: data)
        else {
            return config
        }

        var merged = config
        let hooks = hooksConfig.hooks
        merged.hooksEnabled = !hooks.isEmpty
        merged.enablePreToolUseHook = hooks[CodexHookEventName.preToolUse.rawValue]?.containsActiveCommandHook == true
        merged.enablePostToolUseHook = hooks[CodexHookEventName.postToolUse.rawValue]?.containsActiveCommandHook == true

        if let timeout = hooks[CodexHookEventName.preToolUse.rawValue]?.firstTimeout {
            merged.preToolUseTimeout = timeout
        }

        return merged
    }

    func write(config: SettingsConfig) throws {
        let hooksFile = CodexHooksFile(hooks: hooks(for: config))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try fileManager.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(hooksFile)
        try data.write(to: hooksURL, options: .atomic)
    }

    private func hooks(for config: SettingsConfig) -> [String: [CodexHooksMatcher]] {
        guard config.hooksEnabled else {
            return [:]
        }

        var hooks: [String: [CodexHooksMatcher]] = [
            CodexHookEventName.sessionStart.rawValue: [matcher(timeout: 1)],
            CodexHookEventName.stop.rawValue: [matcher(timeout: 1)],
            CodexHookEventName.userPromptSubmit.rawValue: [matcher(timeout: 1)]
        ]

        if config.enablePreToolUseHook {
            hooks[CodexHookEventName.preToolUse.rawValue] = [matcher(timeout: max(1, config.preToolUseTimeout))]
        }

        if config.enablePostToolUseHook {
            hooks[CodexHookEventName.postToolUse.rawValue] = [matcher(timeout: 1)]
        }

        return hooks
    }

    private func matcher(timeout: Int) -> CodexHooksMatcher {
        CodexHooksMatcher(
            hooks: [
                CodexHooksCommand(
                    type: "command",
                    command: helperCommand,
                    timeout: timeout
                )
            ]
        )
    }

    private static var defaultHelperCommand: String {
        let sourceURL = URL(fileURLWithPath: #filePath)
        let projectURL = sourceURL.deletingLastPathComponent().deletingLastPathComponent()
        return projectURL
            .appendingPathComponent("tools", isDirectory: true)
            .appendingPathComponent("codex_hook_helper.py")
            .path
    }
}

private struct CodexHooksFile: Codable {
    let hooks: [String: [CodexHooksMatcher]]
}

private struct CodexHooksMatcher: Codable {
    let hooks: [CodexHooksCommand]

    var containsActiveCommandHook: Bool {
        hooks.contains { $0.type == "command" }
    }

    var firstTimeout: Int? {
        hooks.first(where: { $0.type == "command" })?.timeout
    }
}

private extension Array where Element == CodexHooksMatcher {
    var containsActiveCommandHook: Bool {
        contains { $0.containsActiveCommandHook }
    }

    var firstTimeout: Int? {
        compactMap(\.firstTimeout).first
    }
}

private struct CodexHooksCommand: Codable {
    let type: String
    let command: String
    let timeout: Int
}
