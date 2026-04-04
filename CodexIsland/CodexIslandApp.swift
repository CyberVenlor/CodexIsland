import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlayController = IslandOverlayController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        overlayController.start()
    }
}

@MainActor
@main
struct CodexIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
