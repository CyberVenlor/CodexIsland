import AppKit
import Foundation

protocol CodexSessionNavigating {
    func open(_ session: CodexSessionGroup) -> Bool
}

struct CodexSessionNavigator: CodexSessionNavigating {
    func open(_ session: CodexSessionGroup) -> Bool {
        guard let target = target(for: session.source) else {
            return false
        }

        return activateApplication(bundleIdentifier: target.bundleIdentifier)
    }

    private func target(for source: CodexThreadSource?) -> CodexSessionNavigationTarget? {
        switch source {
        case .cli:
            return .terminal
        case .vscode:
            return .codex
        case .other, .none:
            return nil
        }
    }

    private func activateApplication(bundleIdentifier: String) -> Bool {
        if let runningApplication = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            return runningApplication.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, _ in }
        return true
    }
}

private enum CodexSessionNavigationTarget {
    case codex
    case terminal

    var bundleIdentifier: String {
        switch self {
        case .codex:
            return "com.openai.codex"
        case .terminal:
            return "com.apple.Terminal"
        }
    }
}
