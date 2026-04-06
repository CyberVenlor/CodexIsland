import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sessionController = CodexSessionController()
    let settingsStore = SettingsConfigStore()
    private lazy var overlayController = IslandOverlayController(
        sessionController: sessionController,
        settingsStore: settingsStore
    )
    private lazy var relayServer = CodexHookRelayServer(sessionController: sessionController)
    private var settingsObservers: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureLaunchAtLogin()
        sessionController.updateHookSettings(settingsStore.config)
        overlayController.start()
        relayServer.start()
    }

    private func configureLaunchAtLogin() {
        syncLaunchAtLoginSetting(enabled: settingsStore.config.launchAtLogin)

        settingsStore.$config
            .map(\.launchAtLogin)
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.syncLaunchAtLoginSetting(enabled: isEnabled)
            }
            .store(in: &settingsObservers)

        settingsStore.$config
            .sink { [weak self] config in
                self?.sessionController.updateHookSettings(config)
            }
            .store(in: &settingsObservers)
    }

    private func syncLaunchAtLoginSetting(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Failed to update launch at login setting: %@", String(describing: error))
        }
    }
}

@MainActor
@main
struct CodexIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsPanelView()
                .environmentObject(appDelegate.settingsStore)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
