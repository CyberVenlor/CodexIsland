import Foundation

struct AppVersion: Hashable, Codable, Comparable, CustomStringConvertible {
    let rawValue: String
    private let numericComponents: [Int]

    init(_ rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        numericComponents = Self.parseComponents(from: self.rawValue)
    }

    var description: String { rawValue }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let maxCount = max(lhs.numericComponents.count, rhs.numericComponents.count)

        for index in 0..<maxCount {
            let left = index < lhs.numericComponents.count ? lhs.numericComponents[index] : 0
            let right = index < rhs.numericComponents.count ? rhs.numericComponents[index] : 0

            if left != right {
                return left < right
            }
        }

        return false
    }

    private static func parseComponents(from rawValue: String) -> [Int] {
        rawValue
            .split(separator: ".")
            .map { component in
                let numericPrefix = component.prefix { $0.isNumber }
                return Int(numericPrefix) ?? 0
            }
    }
}

struct InstalledAppVersion: Equatable {
    let marketingVersion: AppVersion
    let build: Int?

    static var current: InstalledAppVersion {
        let marketingVersion = AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
        let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
        return InstalledAppVersion(marketingVersion: marketingVersion, build: build)
    }
}

struct AppUpdateManifest: Decodable, Equatable {
    let version: AppVersion
    let build: Int?
    let forceUpdate: Bool
    let minimumSupportedVersion: AppVersion?
    let releaseTag: String?
    let assetName: String?
    let releaseNotes: String?
    let securityNotice: String?

    private enum CodingKeys: String, CodingKey {
        case version
        case build
        case forceUpdate = "force_update"
        case minimumSupportedVersion = "minimum_supported_version"
        case releaseTag = "release_tag"
        case assetName = "asset_name"
        case releaseNotes = "release_notes"
        case securityNotice = "security_notice"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = AppVersion(try container.decode(String.self, forKey: .version))
        build = try container.decodeIfPresent(Int.self, forKey: .build)
        forceUpdate = try container.decodeIfPresent(Bool.self, forKey: .forceUpdate) ?? false
        minimumSupportedVersion = try container.decodeIfPresent(String.self, forKey: .minimumSupportedVersion).map(AppVersion.init)
        releaseTag = try container.decodeIfPresent(String.self, forKey: .releaseTag)
        assetName = try container.decodeIfPresent(String.self, forKey: .assetName)
        releaseNotes = try container.decodeIfPresent(String.self, forKey: .releaseNotes)
        securityNotice = try container.decodeIfPresent(String.self, forKey: .securityNotice)
    }
}

struct AppUpdateConfig: Equatable {
    let version: AppVersion
    let build: Int?
    let forceUpdate: Bool
    let minimumSupportedVersion: AppVersion?
    let releaseTag: String?
    let assetName: String?
    let assetURL: URL?
    let releaseNotes: String?
    let securityNotice: String?

    init(xcconfigContents: String) throws {
        let values = Self.parse(contents: xcconfigContents)

        guard let versionValue = values["APP_MARKETING_VERSION"], !versionValue.isEmpty else {
            throw AppUpdateError.invalidVersionConfig("Missing APP_MARKETING_VERSION")
        }

        version = AppVersion(versionValue)
        build = values["APP_BUILD_VERSION"].flatMap(Int.init)
        forceUpdate = Self.parseBool(values["APP_FORCE_UPDATE"])
        minimumSupportedVersion = values["APP_MINIMUM_SUPPORTED_VERSION"].map(AppVersion.init)
        releaseTag = Self.nonEmpty(values["APP_RELEASE_TAG"])
        assetName = Self.nonEmpty(values["APP_RELEASE_ASSET_NAME"])
        assetURL = Self.nonEmpty(values["APP_RELEASE_ASSET_URL"]).flatMap(URL.init(string:))
        releaseNotes = Self.nonEmpty(values["APP_RELEASE_NOTES"])
        securityNotice = Self.nonEmpty(values["APP_SECURITY_NOTICE"])
    }

    private static func parse(contents: String) -> [String: String] {
        var values: [String: String] = [:]

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("//"), !line.hasPrefix("#") else { continue }
            guard let separatorIndex = line.firstIndex(of: "=") else { continue }

            let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = line.index(after: separatorIndex)
            let value = String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            values[key] = value
        }

        return values
    }

    private static func parseBool(_ rawValue: String?) -> Bool {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "yes", "true", "1":
            return true
        default:
            return false
        }
    }

    private static func nonEmpty(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct GitHubReleaseResponse: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        private enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: URL
    let body: String?
    let assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case assets
    }
}

struct AvailableAppUpdate: Equatable {
    let version: AppVersion
    let build: Int?
    let releaseTag: String
    let assetName: String
    let downloadURL: URL
    let releasePageURL: URL
    let releaseNotes: String?
    let securityNotice: String?
    let isMandatory: Bool

    var versionLabel: String {
        if let build {
            return "\(version.rawValue) (\(build))"
        }
        return version.rawValue
    }
}

enum AppUpdatePhase: Equatable {
    case idle
    case checking
    case available(AvailableAppUpdate)
    case downloading(AvailableAppUpdate)
    case installing(AvailableAppUpdate)
    case failed(AvailableAppUpdate, message: String)
}

enum AppUpdateError: LocalizedError, Equatable {
    case invalidHTTPResponse
    case invalidVersionConfig(String)
    case manifestReleaseAssetMissing
    case noZipAssetInRelease
    case downloadedArchiveMissingApp
    case appBundleNotWritable(String)
    case installerLaunchFailed
    case unexpectedStatusCode(Int)

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "Received an invalid response while checking for updates."
        case .invalidVersionConfig(let message):
            return "Invalid version config: \(message)"
        case .manifestReleaseAssetMissing:
            return "The configured release asset could not be found in the GitHub release."
        case .noZipAssetInRelease:
            return "No macOS zip asset was found in the GitHub release."
        case .downloadedArchiveMissingApp:
            return "The downloaded archive did not contain a macOS app bundle."
        case .appBundleNotWritable(let path):
            return "The current app bundle cannot be replaced automatically: \(path)"
        case .installerLaunchFailed:
            return "Failed to launch the installer helper."
        case .unexpectedStatusCode(let code):
            return "GitHub returned HTTP \(code) while checking for updates."
        }
    }
}
