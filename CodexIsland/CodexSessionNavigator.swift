import AppKit
import Foundation

protocol CodexSessionNavigating {
    func open(_ session: CodexSessionGroup) -> Bool
}

struct CodexSessionNavigator: CodexSessionNavigating {
    func open(_ session: CodexSessionGroup) -> Bool {
        switch session.source {
        case .vscode:
            return activateApplication(bundleIdentifier: "com.openai.codex")
        case .cli:
            if let bundleIdentifier = cliHostBundleIdentifier(for: session) {
                return activateApplication(bundleIdentifier: bundleIdentifier)
            }
            return false
        case .other, .none:
            return false
        }
    }

    private func cliHostBundleIdentifier(for session: CodexSessionGroup) -> String? {
        let inspector = CodexCLIProcessInspector()

        if let rolloutPath = session.rolloutPath,
           let bundleIdentifier = inspector.guiAncestorBundleIdentifier(matchingRolloutPath: rolloutPath) {
            return bundleIdentifier
        }

        let bundleIdentifiers = inspector.guiAncestorBundleIdentifiersForRunningCodexProcesses()
        if bundleIdentifiers.count == 1 {
            return bundleIdentifiers.first
        }

        return nil
    }

    private func activateApplication(bundleIdentifier: String) -> Bool {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }

        if let runningApplication = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
           runningApplication.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) {
            return true
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, _ in }
        return true
    }
}

private struct CodexCLIProcessInspector {
    func guiAncestorBundleIdentifier(matchingRolloutPath rolloutPath: String) -> String? {
        for pid in codexPIDs() {
            guard openFiles(forPID: pid).contains(rolloutPath) else {
                continue
            }

            if let bundleIdentifier = guiAncestorBundleIdentifier(forPID: pid) {
                return bundleIdentifier
            }
        }

        return nil
    }

    func guiAncestorBundleIdentifiersForRunningCodexProcesses() -> Set<String> {
        Set(codexPIDs().compactMap(guiAncestorBundleIdentifier(forPID:)))
    }

    private func codexPIDs() -> [Int32] {
        shell("/usr/bin/pgrep", arguments: ["-x", "codex"])
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func openFiles(forPID pid: Int32) -> Set<String> {
        let output = shell("/usr/sbin/lsof", arguments: ["-p", String(pid), "-Fn"])
        return Set(
            output
                .split(whereSeparator: \.isNewline)
                .compactMap { line -> String? in
                    guard line.first == "n" else {
                        return nil
                    }

                    let path = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                    return path.isEmpty ? nil : path
                }
        )
    }

    private func guiAncestorBundleIdentifier(forPID pid: Int32) -> String? {
        var currentPID = pid
        var visited = Set<Int32>()

        while currentPID > 1, !visited.contains(currentPID) {
            visited.insert(currentPID)

            guard let processInfo = processInfo(forPID: currentPID) else {
                return nil
            }

            if let appURL = applicationURL(fromExecutablePath: processInfo.command),
               let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier {
                return bundleIdentifier
            }

            currentPID = processInfo.ppid
        }

        return nil
    }

    private func processInfo(forPID pid: Int32) -> ProcessInfoRecord? {
        let output = shell("/bin/ps", arguments: ["-p", String(pid), "-o", "pid=,ppid=,comm="])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            return nil
        }

        let components = output.split(maxSplits: 2, whereSeparator: \.isWhitespace)
        guard components.count == 3,
              let resolvedPID = Int32(components[0]),
              let parentPID = Int32(components[1]) else {
            return nil
        }

        return ProcessInfoRecord(
            pid: resolvedPID,
            ppid: parentPID,
            command: String(components[2])
        )
    }

    private func applicationURL(fromExecutablePath executablePath: String) -> URL? {
        guard let appRange = executablePath.range(of: ".app/") else {
            return nil
        }

        let appPath = String(executablePath[..<appRange.upperBound].dropLast())
        return URL(fileURLWithPath: appPath)
    }

    private func shell(_ launchPath: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return ""
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return ""
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct ProcessInfoRecord {
    let pid: Int32
    let ppid: Int32
    let command: String
}
