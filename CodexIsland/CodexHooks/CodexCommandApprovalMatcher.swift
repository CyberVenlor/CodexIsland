import Foundation

enum CodexCommandApprovalMatcher {
    static func requiresApproval(for context: CodexPreToolUseContext) -> Bool {
        requiresApproval(toolName: context.toolName, command: context.toolInput.command)
    }

    static func requiresApproval(toolName: CodexToolName, command: String) -> Bool {
        if toolName.displayName != "Bash" {
            return true
        }

        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }

        if containsDynamicOrUnsafeShellSyntax(trimmed) {
            return true
        }

        let tokens = shellTokens(trimmed)
        if tokens.isEmpty {
            return true
        }

        return !shellStructureIsSafe(tokens)
    }

    private static func containsDynamicOrUnsafeShellSyntax(_ command: String) -> Bool {
        let characters = Array(command)
        var index = 0
        var quote: Character?

        while index < characters.count {
            let character = characters[index]

            if quote == "'" {
                if character == "'" {
                    quote = nil
                }
                index += 1
                continue
            }

            if quote == "\"" {
                if character == "\"" {
                    quote = nil
                    index += 1
                    continue
                }

                if character == "\\" {
                    index += 2
                    continue
                }

                if character == "`" {
                    return true
                }

                if character == "$", characters[safe: index + 1] == "(" {
                    return true
                }

                index += 1
                continue
            }

            if character == "\\" {
                index += 2
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
                index += 1
                continue
            }

            if character == "`" || character == ">" || character == "<" {
                return true
            }

            if character == "$", characters[safe: index + 1] == "(" {
                return true
            }

            index += 1
        }

        return false
    }

    private static func shellTokens(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        let characters = Array(command)
        var index = 0
        var quote: Character?

        while index < characters.count {
            let character = characters[index]

            if let currentQuote = quote {
                if character == currentQuote {
                    quote = nil
                } else if character == "\\", currentQuote == "\"", let next = characters[safe: index + 1] {
                    current.append(next)
                    index += 1
                } else {
                    current.append(character)
                }
                index += 1
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
                index += 1
                continue
            }

            if character == "\\" {
                if let next = characters[safe: index + 1] {
                    current.append(next)
                    index += 2
                } else {
                    index += 1
                }
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                index += 1
                continue
            }

            current.append(character)
            index += 1
        }

        if quote != nil {
            return []
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    private static func shellStructureIsSafe(_ tokens: [String]) -> Bool {
        guard let first = tokens.first else {
            return false
        }

        if first.hasPrefix("-") {
            return false
        }

        return first == "pwd"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
