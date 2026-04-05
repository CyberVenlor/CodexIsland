import Foundation

enum CodexCommandApprovalMatcher {
    static func requiresApproval(for context: CodexPreToolUseContext) -> Bool {
        requiresApproval(toolName: context.toolName, command: context.toolInput.command)
    }

    static func requiresApproval(toolName: CodexToolName, command: String) -> Bool {
        guard case .bash = toolName else {
            return true
        }

        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }

        if containsRiskyShellSyntax(trimmed) {
            return true
        }

        let tokens = shellTokens(from: trimmed)
        guard !tokens.isEmpty else {
            return true
        }

        if looksLikeEnvironmentAssignment(tokens[0]) {
            return true
        }

        let executable = URL(fileURLWithPath: tokens[0]).lastPathComponent

        if isSafeInspectionCommand(tokens, executable: executable) {
            return false
        }

        switch executable {
        case "git":
            return !isSafeGitCommand(tokens)
        case "swift":
            return !isSafeSwiftCommand(tokens)
        case "xcodebuild":
            return !isSafeXcodeBuildCommand(tokens)
        case "npm", "pnpm", "yarn", "bun":
            return !isSafeJavaScriptCommand(tokens)
        default:
            return true
        }
    }

    private static let safeInspectionCommands: Set<String> = [
        "cat", "du", "fd", "file", "grep", "head", "ls",
        "pwd", "rg", "stat", "tail", "tree", "uname", "wc", "which", "whoami"
    ]

    private static func containsRiskyShellSyntax(_ command: String) -> Bool {
        let riskyFragments = ["&&", "||", ";", "|", ">", "<", "&", "$(", "`"]
        return riskyFragments.contains { command.contains($0) }
    }

    private static func looksLikeEnvironmentAssignment(_ token: String) -> Bool {
        guard let equalIndex = token.firstIndex(of: "="), equalIndex != token.startIndex else {
            return false
        }

        let key = token[..<equalIndex]
        return key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func isSafeInspectionCommand(_ tokens: [String], executable: String) -> Bool {
        if safeInspectionCommands.contains(executable) {
            return true
        }

        switch executable {
        case "sed":
            return !tokens.dropFirst().contains { $0 == "-i" || $0 == "--in-place" }
        case "find":
            let blockedFlags: Set<String> = ["-delete", "-exec", "-execdir", "-ok", "-okdir"]
            return !tokens.dropFirst().contains { blockedFlags.contains($0) }
        default:
            return false
        }
    }

    private static func isSafeGitCommand(_ tokens: [String]) -> Bool {
        guard tokens.count >= 2 else {
            return false
        }

        switch tokens[1] {
        case "status", "diff", "log", "show", "rev-parse", "grep", "ls-files":
            return true
        case "branch":
            return tokens.count == 2 || tokens.dropFirst(2).allSatisfy { $0 == "--show-current" || $0 == "--all" }
        default:
            return false
        }
    }

    private static func isSafeSwiftCommand(_ tokens: [String]) -> Bool {
        guard tokens.count >= 2 else {
            return false
        }

        switch tokens[1] {
        case "build", "test":
            return true
        case "package":
            guard tokens.count >= 3 else {
                return false
            }
            return ["describe", "dump-package"].contains(tokens[2])
        default:
            return false
        }
    }

    private static func isSafeXcodeBuildCommand(_ tokens: [String]) -> Bool {
        let safeFlags: Set<String> = ["-list", "-showBuildSettings"]
        let safeActions: Set<String> = ["build", "test"]

        return tokens.dropFirst().contains { safeFlags.contains($0) || safeActions.contains($0) }
    }

    private static func isSafeJavaScriptCommand(_ tokens: [String]) -> Bool {
        guard tokens.count >= 2 else {
            return false
        }

        return tokens[1] == "test"
    }

    private static func shellTokens(from command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var iterator = command.makeIterator()

        while let character = iterator.next() {
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
            case " ", "\t", "\n":
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
            case "\\":
                if let escaped = iterator.next() {
                    current.append(escaped)
                }
            default:
                current.append(character)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
