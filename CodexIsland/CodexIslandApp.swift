//
//  CodexIslandApp.swift
//  CodexIsland
//
//  Created by n3ur0 on 4/4/26.
//

import SwiftUI

@main
struct CodexIslandApp: App {
    @StateObject private var sessionController: CodexSessionController
    private let relayServer: CodexHookRelayServer

    init() {
        let sessionController = CodexSessionController()
        _sessionController = StateObject(wrappedValue: sessionController)
        relayServer = CodexHookRelayServer(sessionController: sessionController)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionController)
                .task {
                    relayServer.start()
                }
        }
    }
}
