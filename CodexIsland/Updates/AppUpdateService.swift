import AppKit
import Foundation

protocol AppUpdateServing {
    func checkForUpdates() async throws -> AvailableAppUpdate?
    func installUpdate(_ update: AvailableAppUpdate) async throws
}

final class GitHubAppUpdateService: AppUpdateServing {
    private let owner: String
    private let repository: String
    private let manifestURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let fileManager: FileManager

    init(
        owner: String,
        repository: String,
        manifestURL: URL,
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.owner = owner
        self.repository = repository
        self.manifestURL = manifestURL
        self.session = session
        self.fileManager = fileManager
    }

    func checkForUpdates() async throws -> AvailableAppUpdate? {
        let manifest: AppUpdateManifest = try await fetchDecodable(from: manifestURL)
        let installedVersion = InstalledAppVersion.current

        guard manifest.version > installedVersion.marketingVersion
            || (manifest.version == installedVersion.marketingVersion && (manifest.build ?? 0) > (installedVersion.build ?? 0))
        else {
            return nil
        }

        let release = try await fetchRelease(for: manifest)
        let asset = try selectAsset(from: release, preferredName: manifest.assetName)
        let isMandatory = manifest.forceUpdate
            || manifest.minimumSupportedVersion.map { installedVersion.marketingVersion < $0 } == true

        return AvailableAppUpdate(
            version: manifest.version,
            build: manifest.build,
            releaseTag: release.tagName,
            assetName: asset.name,
            downloadURL: asset.browserDownloadURL,
            releasePageURL: release.htmlURL,
            releaseNotes: manifest.releaseNotes ?? release.body,
            securityNotice: manifest.securityNotice,
            isMandatory: isMandatory
        )
    }

    func installUpdate(_ update: AvailableAppUpdate) async throws {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let parentDirectory = bundleURL.deletingLastPathComponent()

        guard fileManager.isWritableFile(atPath: parentDirectory.path) else {
            throw AppUpdateError.appBundleNotWritable(parentDirectory.path)
        }

        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CodexIslandUpdate-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        let archiveURL = try await downloadAsset(from: update.downloadURL, into: stagingRoot)
        let stagedAppURL = try await extractApp(from: archiveURL, into: stagingRoot)
        try launchInstaller(stagedAppURL: stagedAppURL, targetAppURL: bundleURL)

        await MainActor.run {
            NSApp.terminate(nil)
        }
    }

    private func fetchRelease(for manifest: AppUpdateManifest) async throws -> GitHubReleaseResponse {
        let endpoint: URL

        if let tag = manifest.releaseTag, !tag.isEmpty {
            endpoint = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/tags/\(tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag)")!
        } else {
            endpoint = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
        }

        return try await fetchDecodable(from: endpoint)
    }

    private func fetchDecodable<T: Decodable>(from url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CodexIsland", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func downloadAsset(from url: URL, into directory: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("CodexIsland", forHTTPHeaderField: "User-Agent")

        let (temporaryURL, response) = try await session.download(for: request)
        try validate(response: response)

        let destinationURL = directory.appendingPathComponent(url.lastPathComponent)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private func extractApp(from archiveURL: URL, into directory: URL) async throws -> URL {
        let extractionURL = directory.appendingPathComponent("Extracted", isDirectory: true)
        try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        try await runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", archiveURL.path, extractionURL.path]
        )

        guard let appURL = fileManager.enumerator(at: extractionURL, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL })
            .first(where: { $0.pathExtension == "app" }) else {
            throw AppUpdateError.downloadedArchiveMissingApp
        }

        return appURL
    }

    private func selectAsset(
        from release: GitHubReleaseResponse,
        preferredName: String?
    ) throws -> GitHubReleaseResponse.Asset {
        if let preferredName,
           let asset = release.assets.first(where: { $0.name == preferredName }) {
            return asset
        }

        if preferredName != nil {
            throw AppUpdateError.manifestReleaseAssetMissing
        }

        guard let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) else {
            throw AppUpdateError.noZipAssetInRelease
        }

        return asset
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidHTTPResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AppUpdateError.unexpectedStatusCode(httpResponse.statusCode)
        }
    }

    private func runProcess(executableURL: URL, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: AppUpdateError.installerLaunchFailed)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func launchInstaller(stagedAppURL: URL, targetAppURL: URL) throws {
        let installerRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CodexIslandInstaller-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: installerRoot, withIntermediateDirectories: true)

        let scriptURL = installerRoot.appendingPathComponent("install-update.sh")
        let script = """
        #!/bin/zsh
        set -eu
        APP_PID="$1"
        SOURCE_APP="$2"
        TARGET_APP="$3"

        while kill -0 "$APP_PID" >/dev/null 2>&1; do
          sleep 0.2
        done

        /bin/rm -rf "$TARGET_APP"
        /usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"
        /usr/bin/open "$TARGET_APP"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            "\(ProcessInfo.processInfo.processIdentifier)",
            stagedAppURL.path,
            targetAppURL.path
        ]

        do {
            try process.run()
        } catch {
            throw AppUpdateError.installerLaunchFailed
        }
    }
}
