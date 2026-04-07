import Combine
import Foundation

@MainActor
final class AppUpdateController: ObservableObject {
    @Published private(set) var phase: AppUpdatePhase = .idle

    private let service: AppUpdateServing
    private var hasCheckedAtLaunch = false

    init(service: AppUpdateServing) {
        self.service = service
    }

    var currentUpdate: AvailableAppUpdate? {
        switch phase {
        case .available(let update), .unavailable(let update, _), .downloading(let update), .installing(let update), .failed(let update, _):
            return update
        case .idle, .checking:
            return nil
        }
    }

    var isMandatory: Bool {
        currentUpdate?.isMandatory ?? false
    }

    var errorMessage: String? {
        if case .failed(_, let message) = phase {
            return message
        }
        if case .unavailable(_, let message) = phase {
            return message
        }
        return nil
    }

    var isBusy: Bool {
        switch phase {
        case .downloading, .installing, .checking:
            return true
        case .idle, .available, .unavailable, .failed:
            return false
        }
    }

    func checkForUpdatesAtLaunchIfNeeded() {
        guard !hasCheckedAtLaunch else { return }
        hasCheckedAtLaunch = true
        log("Launch-triggered update check scheduled.")
        checkForUpdates()
    }

    func checkForUpdates() {
        if case .checking = phase {
            log("Update check skipped because a check is already running.")
            return
        }

        phase = .checking
        log("Phase changed to checking.")
        Task { await performCheck() }
    }

    func startUpdate() {
        guard let update = currentUpdate else { return }
        guard !isBusy else { return }

        phase = .downloading(update)
        log("User accepted update. version=\(update.versionLabel) mandatory=\(update.isMandatory)")
        Task { await performInstall(update) }
    }

    func dismissUpdate() {
        guard let update = currentUpdate else { return }
        guard !update.isMandatory else { return }
        guard !isBusy else { return }
        phase = .idle
        log("User dismissed optional update for version \(update.versionLabel).")
    }

    private func performCheck() async {
        do {
            switch try await service.checkForUpdates() {
            case .none:
                phase = .idle
                log("Update check completed. No newer version found.")
            case .available(let update):
                phase = .available(update)
                log("Phase changed to available. version=\(update.versionLabel) mandatory=\(update.isMandatory)")
            case .unavailable(let update, let message):
                phase = .unavailable(update, message: message)
                log("Phase changed to unavailable. version=\(update.versionLabel) error=\(message)")
            }
        } catch {
            phase = .idle
            log("Update check failed: \(error.localizedDescription)")
        }
    }

    private func performInstall(_ update: AvailableAppUpdate) async {
        do {
            log("Install task started for version \(update.versionLabel).")
            try await service.installUpdate(update)
            phase = .installing(update)
            log("Phase changed to installing for version \(update.versionLabel).")
        } catch {
            phase = .failed(update, message: error.localizedDescription)
            log("Install failed for version \(update.versionLabel): \(error.localizedDescription)")
        }
    }

    private func log(_ message: String) {
        NSLog("[AppUpdate] %@", message)
    }
}
