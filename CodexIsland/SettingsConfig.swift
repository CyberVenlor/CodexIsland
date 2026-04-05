//
//  SettingsConfig.swift
//  CodexIsland
//
//  Created by Codex on 4/5/26.
//

import Combine
import Foundation

struct SettingsConfig: Codable {
    var launchAtLogin = true
    var openOnStartup = true
    var displayName = "Faker"
    var preferredLanguage = "English"
    var hooksEnabled = true
    var enablePreHook = false
    var enablePostHook = true
    var hookURL = "https://hooks.modulusly.dev"
}

@MainActor
final class SettingsConfigStore: ObservableObject {
    @Published var config: SettingsConfig {
        didSet {
            save()
        }
    }

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let configURL: URL

    init(fileManager: FileManager = .default) {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = appSupportURL.appendingPathComponent("CodexIsland", isDirectory: true)
        let configURL = directoryURL.appendingPathComponent("settings.json")
        let decoder = JSONDecoder()

        self.fileManager = fileManager
        self.configURL = configURL
        self.config = Self.loadConfig(fileManager: fileManager, decoder: decoder, configURL: configURL)
        save()
    }

    private static func loadConfig(
        fileManager: FileManager,
        decoder: JSONDecoder,
        configURL: URL
    ) -> SettingsConfig {
        guard fileManager.fileExists(atPath: configURL.path) else {
            return SettingsConfig()
        }

        do {
            let data = try Data(contentsOf: configURL)
            return try decoder.decode(SettingsConfig.self, from: data)
        } catch {
            return SettingsConfig()
        }
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            assertionFailure("Failed to save settings config: \(error)")
        }
    }
}
