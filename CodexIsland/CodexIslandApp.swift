//
//  CodexIslandApp.swift
//  CodexIsland
//
//  Created by n3ur0 on 4/4/26.
//

import SwiftUI

@main
struct CodexIslandApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 280)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
