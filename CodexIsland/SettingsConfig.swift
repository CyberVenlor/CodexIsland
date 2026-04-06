import Combine
import Foundation

struct SettingsConfig: Codable, Equatable {
    var launchAtLogin = true
    var displayName = "Faker"
    var preferredLanguage = "English"
    var hooksEnabled = true
    var enablePreToolUseHook = true
    var enablePostToolUseHook = false
    var preToolUseTimeout = 300
    var suspiciousSessionTimeout = 60
    var completedIslandDisplayDuration = 2
    var suspiciousIslandDisplayDuration = 2
    var showSessionEndNotifications = true
    var codexExternalApprovalModeEnabled = false

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case displayName
        case preferredLanguage
        case hooksEnabled
        case enablePreToolUseHook
        case enablePostToolUseHook
        case preToolUseTimeout
        case suspiciousSessionTimeout
        case completedIslandDisplayDuration
        case suspiciousIslandDisplayDuration
        case showSessionEndNotifications
        case codexExternalApprovalModeEnabled
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
        suspiciousSessionTimeout = max(1, try container.decodeIfPresent(Int.self, forKey: .suspiciousSessionTimeout) ?? 60)
        completedIslandDisplayDuration = max(0, try container.decodeIfPresent(Int.self, forKey: .completedIslandDisplayDuration) ?? 2)
        suspiciousIslandDisplayDuration = max(0, try container.decodeIfPresent(Int.self, forKey: .suspiciousIslandDisplayDuration) ?? 2)
        showSessionEndNotifications = try container.decodeIfPresent(Bool.self, forKey: .showSessionEndNotifications) ?? true
        codexExternalApprovalModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .codexExternalApprovalModeEnabled) ?? false
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
        try container.encode(suspiciousSessionTimeout, forKey: .suspiciousSessionTimeout)
        try container.encode(completedIslandDisplayDuration, forKey: .completedIslandDisplayDuration)
        try container.encode(suspiciousIslandDisplayDuration, forKey: .suspiciousIslandDisplayDuration)
        try container.encode(showSessionEndNotifications, forKey: .showSessionEndNotifications)
        try container.encode(codexExternalApprovalModeEnabled, forKey: .codexExternalApprovalModeEnabled)
    }
}

@MainActor
final class SettingsConfigStore: ObservableObject {
    private static let saveDebounceDelay: TimeInterval = 0.18

    @Published var config: SettingsConfig {
        didSet {
            guard oldValue != config else { return }
            scheduleSave()
        }
    }

    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let configURL: URL
    private let hooksConfigStore: CodexHooksConfigStore
    private let codexCLIConfigStore: CodexCLIConfigStore
    private let saveQueue = DispatchQueue(
        label: "CodexIsland.SettingsConfigStore.save",
        qos: .utility
    )
    private var pendingSaveWorkItem: DispatchWorkItem?

    init(
        fileManager: FileManager = .default,
        hooksConfigStore: CodexHooksConfigStore = CodexHooksConfigStore(),
        codexCLIConfigStore: CodexCLIConfigStore = CodexCLIConfigStore()
    ) {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = appSupportURL.appendingPathComponent("CodexIsland", isDirectory: true)
        let configURL = directoryURL.appendingPathComponent("settings.json")

        self.fileManager = fileManager
        self.configURL = configURL
        self.hooksConfigStore = hooksConfigStore
        self.codexCLIConfigStore = codexCLIConfigStore
        self.config = Self.loadConfig(
            fileManager: fileManager,
            decoder: decoder,
            configURL: configURL,
            hooksConfigStore: hooksConfigStore,
            codexCLIConfigStore: codexCLIConfigStore
        )
        scheduleSave(immediately: true)
    }

    private static func loadConfig(
        fileManager: FileManager,
        decoder: JSONDecoder,
        configURL: URL,
        hooksConfigStore: CodexHooksConfigStore,
        codexCLIConfigStore: CodexCLIConfigStore
    ) -> SettingsConfig {
        let baseConfig: SettingsConfig

        if fileManager.fileExists(atPath: configURL.path),
           let data = try? Data(contentsOf: configURL),
           let decoded = try? decoder.decode(SettingsConfig.self, from: data) {
            baseConfig = decoded
        } else {
            baseConfig = SettingsConfig()
        }

        return codexCLIConfigStore.mergingCLIConfig(into: hooksConfigStore.mergingHooksConfig(into: baseConfig))
    }

    deinit {
        pendingSaveWorkItem?.cancel()
    }

    private func scheduleSave(immediately: Bool = false) {
        let snapshot = config
        let fileManager = fileManager
        let configURL = configURL
        let hooksConfigStore = hooksConfigStore
        let codexCLIConfigStore = codexCLIConfigStore
        pendingSaveWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            do {
                try Self.persist(
                    config: snapshot,
                    fileManager: fileManager,
                    configURL: configURL,
                    hooksConfigStore: hooksConfigStore,
                    codexCLIConfigStore: codexCLIConfigStore
                )
            } catch {
                NSLog("Failed to save settings config: %@", String(describing: error))
            }
        }

        pendingSaveWorkItem = workItem

        if immediately {
            saveQueue.async(execute: workItem)
        } else {
            saveQueue.asyncAfter(deadline: .now() + Self.saveDebounceDelay, execute: workItem)
        }
    }

    private static func persist(
        config: SettingsConfig,
        fileManager: FileManager,
        configURL: URL,
        hooksConfigStore: CodexHooksConfigStore,
        codexCLIConfigStore: CodexCLIConfigStore
    ) throws {
        try fileManager.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(config)
        try data.write(to: configURL, options: .atomic)
        try hooksConfigStore.write(config: config)
        try codexCLIConfigStore.write(config: config)
    }

    func setCodexExternalApprovalModeEnabled(_ isEnabled: Bool) {
        guard config.codexExternalApprovalModeEnabled != isEnabled else { return }
        config.codexExternalApprovalModeEnabled = isEnabled
    }
}
