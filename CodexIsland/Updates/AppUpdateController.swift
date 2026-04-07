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
        case .available(let update), .downloading(let update), .installing(let update), .failed(let update, _):
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
        return nil
    }

    var isBusy: Bool {
        switch phase {
        case .downloading, .installing, .checking:
            return true
        case .idle, .available, .failed:
            return false
        }
    }

    func checkForUpdatesAtLaunchIfNeeded() {
        guard !hasCheckedAtLaunch else { return }
        hasCheckedAtLaunch = true
        checkForUpdates()
    }

    func checkForUpdates() {
        if case .checking = phase {
            return
        }

        phase = .checking
        Task { await performCheck() }
    }

    func startUpdate() {
        guard let update = currentUpdate else { return }
        guard !isBusy else { return }

        phase = .downloading(update)
        Task { await performInstall(update) }
    }

    func dismissUpdate() {
        guard let update = currentUpdate else { return }
        guard !update.isMandatory else { return }
        guard !isBusy else { return }
        phase = .idle
    }

    private func performCheck() async {
        do {
            if let update = try await service.checkForUpdates() {
                phase = .available(update)
            } else {
                phase = .idle
            }
        } catch {
            phase = .idle
            NSLog("Failed to check for updates: %@", error.localizedDescription)
        }
    }

    private func performInstall(_ update: AvailableAppUpdate) async {
        do {
            try await service.installUpdate(update)
            phase = .installing(update)
        } catch {
            phase = .failed(update, message: error.localizedDescription)
        }
    }
}
