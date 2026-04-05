//
//  CodexIslandApp.swift
//  CodexIsland
//
//  Created by n3ur0 on 4/4/26.
//

import SwiftUI

@main
struct CodexIslandApp: App {
    @StateObject private var settingsStore = SettingsConfigStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settingsStore)
        }
    }
}
