import AppKit
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        overlayController.start()
        relayServer.start()
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
