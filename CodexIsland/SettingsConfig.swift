import Combine
import Foundation

struct SettingsConfig: Codable {
    var launchAtLogin = true
    var displayName = "Faker"
    var preferredLanguage = "English"
    var hooksEnabled = true
    var enablePreToolUseHook = true
    var enablePostToolUseHook = false
    var preToolUseTimeout = 300
    var showSessionEndNotifications = true

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case displayName
        case preferredLanguage
        case hooksEnabled
        case enablePreToolUseHook
        case enablePostToolUseHook
        case preToolUseTimeout
        case showSessionEndNotifications
        case legacyEnablePreHook = "enablePreHook"
        case legacyEnablePostHook = "enablePostHook"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "Faker"
        preferredLanguage = try container.decodeIfPresent(String.self, forKey: .preferredLanguage) ?? "English"
        hooksEnabled = try container.decodeIfPresent(Bool.self, forKey: .hooksEnabled) ?? true
        enablePreToolUseHook = try container.decodeIfPresent(Bool.self, forKey: .enablePreToolUseHook)
            ?? container.decodeIfPresent(Bool.self, forKey: .legacyEnablePreHook)
            ?? true
        enablePostToolUseHook = try container.decodeIfPresent(Bool.self, forKey: .enablePostToolUseHook)
            ?? container.decodeIfPresent(Bool.self, forKey: .legacyEnablePostHook)
            ?? false
        preToolUseTimeout = max(1, try container.decodeIfPresent(Int.self, forKey: .preToolUseTimeout) ?? 300)
        showSessionEndNotifications = try container.decodeIfPresent(Bool.self, forKey: .showSessionEndNotifications) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(preferredLanguage, forKey: .preferredLanguage)
        try container.encode(hooksEnabled, forKey: .hooksEnabled)
        try container.encode(enablePreToolUseHook, forKey: .enablePreToolUseHook)
        try container.encode(enablePostToolUseHook, forKey: .enablePostToolUseHook)
        try container.encode(preToolUseTimeout, forKey: .preToolUseTimeout)
        try container.encode(showSessionEndNotifications, forKey: .showSessionEndNotifications)
    }
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
    private let hooksConfigStore: CodexHooksConfigStore

    init(
        fileManager: FileManager = .default,
        hooksConfigStore: CodexHooksConfigStore = CodexHooksConfigStore()
    ) {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = appSupportURL.appendingPathComponent("CodexIsland", isDirectory: true)
        let configURL = directoryURL.appendingPathComponent("settings.json")

        self.fileManager = fileManager
        self.configURL = configURL
        self.hooksConfigStore = hooksConfigStore
        self.config = Self.loadConfig(
            fileManager: fileManager,
            decoder: decoder,
            configURL: configURL,
            hooksConfigStore: hooksConfigStore
        )
        save()
    }

    private static func loadConfig(
        fileManager: FileManager,
        decoder: JSONDecoder,
        configURL: URL,
        hooksConfigStore: CodexHooksConfigStore
    ) -> SettingsConfig {
        let baseConfig: SettingsConfig

        if fileManager.fileExists(atPath: configURL.path),
           let data = try? Data(contentsOf: configURL),
           let decoded = try? decoder.decode(SettingsConfig.self, from: data) {
            baseConfig = decoded
        } else {
            baseConfig = SettingsConfig()
        }

        return hooksConfigStore.mergingHooksConfig(into: baseConfig)
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)
            try hooksConfigStore.write(config: config)
        } catch {
            assertionFailure("Failed to save settings config: \(error)")
        }
    }
}
