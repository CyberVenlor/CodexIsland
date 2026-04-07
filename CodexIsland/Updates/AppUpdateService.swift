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
        log("Starting update check. configURL=\(manifestURL.absoluteString)")
        let versionConfig = try await fetchVersionConfig(from: manifestURL)
        let installedVersion = InstalledAppVersion.current
        log(
            "Manifest loaded. installed=\(installedVersion.marketingVersion.rawValue) build=\(installedVersion.build.map(String.init) ?? "nil") " +
            "remote=\(versionConfig.version.rawValue) build=\(versionConfig.build.map(String.init) ?? "nil") force=\(versionConfig.forceUpdate)"
        )

        guard versionConfig.version > installedVersion.marketingVersion
            || (versionConfig.version == installedVersion.marketingVersion && (versionConfig.build ?? 0) > (installedVersion.build ?? 0))
        else {
            log("No update available. Manifest version is not newer than installed build.")
            return nil
        }

        let release = try await fetchRelease(for: versionConfig)
        let asset = try selectAsset(
            from: release,
            preferredName: versionConfig.assetName,
            preferredURL: versionConfig.assetURL
        )
        let isMandatory = versionConfig.forceUpdate
            || versionConfig.minimumSupportedVersion.map { installedVersion.marketingVersion < $0 } == true
        log(
            "Update available. releaseTag=\(release.tagName) asset=\(asset.name) mandatory=\(isMandatory)"
        )

        return AvailableAppUpdate(
            version: versionConfig.version,
            build: versionConfig.build,
            releaseTag: release.tagName,
            assetName: asset.name,
            downloadURL: asset.browserDownloadURL,
            releasePageURL: release.htmlURL,
            releaseNotes: versionConfig.releaseNotes ?? release.body,
            securityNotice: versionConfig.securityNotice,
            isMandatory: isMandatory
        )
    }

    func installUpdate(_ update: AvailableAppUpdate) async throws {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let parentDirectory = bundleURL.deletingLastPathComponent()
        log("Preparing installation. bundleURL=\(bundleURL.path) parent=\(parentDirectory.path)")

        guard fileManager.isWritableFile(atPath: parentDirectory.path) else {
            log("Install aborted. Parent directory is not writable: \(parentDirectory.path)")
            throw AppUpdateError.appBundleNotWritable(parentDirectory.path)
        }

        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CodexIslandUpdate-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        log("Created staging directory: \(stagingRoot.path)")

        let archiveURL = try await downloadAsset(from: update.downloadURL, into: stagingRoot)
        let stagedAppURL = try await extractApp(from: archiveURL, into: stagingRoot)
        log("Staged app extracted at: \(stagedAppURL.path)")
        try launchInstaller(stagedAppURL: stagedAppURL, targetAppURL: bundleURL)
        log("Installer helper launched. Terminating current app to allow replacement.")

        await MainActor.run {
            NSApp.terminate(nil)
        }
    }

    private func fetchRelease(for manifest: AppUpdateConfig) async throws -> GitHubReleaseResponse {
        let endpoint: URL

        if let tag = manifest.releaseTag, !tag.isEmpty {
            endpoint = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/tags/\(tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag)")!
            log("Fetching release by tag: \(tag)")
        } else {
            endpoint = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
            log("Fetching latest release because manifest release_tag is empty.")
        }

        return try await fetchDecodable(from: endpoint)
    }

    private func fetchVersionConfig(from url: URL) async throws -> AppUpdateConfig {
        var request = URLRequest(url: url)
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        request.setValue("CodexIsland", forHTTPHeaderField: "User-Agent")
        log("HTTP GET \(url.absoluteString)")

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        log("HTTP success \(url.absoluteString) bytes=\(data.count)")

        guard let contents = String(data: data, encoding: .utf8) else {
            throw AppUpdateError.invalidVersionConfig("Unable to decode config as UTF-8")
        }

        return try AppUpdateConfig(xcconfigContents: contents)
    }

    private func fetchDecodable<T: Decodable>(from url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CodexIsland", forHTTPHeaderField: "User-Agent")
        log("HTTP GET \(url.absoluteString)")

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        log("HTTP success \(url.absoluteString) bytes=\(data.count)")
        return try decoder.decode(T.self, from: data)
    }

    private func downloadAsset(from url: URL, into directory: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("CodexIsland", forHTTPHeaderField: "User-Agent")
        log("Downloading asset from \(url.absoluteString)")

        let (temporaryURL, response) = try await session.download(for: request)
        try validate(response: response)

        let destinationURL = directory.appendingPathComponent(url.lastPathComponent)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        log("Asset downloaded to \(destinationURL.path)")
        return destinationURL
    }

    private func extractApp(from archiveURL: URL, into directory: URL) async throws -> URL {
        let extractionURL = directory.appendingPathComponent("Extracted", isDirectory: true)
        try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        log("Extracting archive \(archiveURL.lastPathComponent) to \(extractionURL.path)")
        try await runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", archiveURL.path, extractionURL.path]
        )

        guard let appURL = fileManager.enumerator(at: extractionURL, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL })
            .first(where: { $0.pathExtension == "app" }) else {
            log("Extraction finished but no .app bundle was found.")
            throw AppUpdateError.downloadedArchiveMissingApp
        }

        log("Found extracted app bundle: \(appURL.path)")
        return appURL
    }

    private func selectAsset(
        from release: GitHubReleaseResponse,
        preferredName: String?,
        preferredURL: URL?
    ) throws -> GitHubReleaseResponse.Asset {
        let availableAssetNames = release.assets.map(\.name).joined(separator: ", ")

        if let preferredURL,
           let asset = release.assets.first(where: { $0.browserDownloadURL == preferredURL }) {
            log("Matched preferred asset URL from version config: \(preferredURL.absoluteString)")
            return asset
        }

        if let preferredName,
           let asset = release.assets.first(where: { $0.name == preferredName }) {
            log("Matched preferred asset from manifest: \(preferredName)")
            return asset
        }

        if preferredURL != nil || preferredName != nil {
            log(
                "Preferred asset from version config was not found. " +
                "preferredURL=\(preferredURL?.absoluteString ?? "nil") " +
                "preferredName=\(preferredName ?? "nil") " +
                "available=\(availableAssetNames)"
            )
            throw AppUpdateError.manifestReleaseAssetMissing
        }

        guard let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) else {
            log("No .zip asset found in release. available=\(availableAssetNames)")
            throw AppUpdateError.noZipAssetInRelease
        }

        log("Selected fallback zip asset: \(asset.name)")
        return asset
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            log("Received invalid non-HTTP response.")
            throw AppUpdateError.invalidHTTPResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            log("HTTP request failed with status \(httpResponse.statusCode)")
            throw AppUpdateError.unexpectedStatusCode(httpResponse.statusCode)
        }
    }

    private func runProcess(executableURL: URL, arguments: [String]) async throws {
        log("Launching process: \(executableURL.path) \(arguments.joined(separator: " "))")
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    self.log("Process finished successfully: \(executableURL.lastPathComponent)")
                    continuation.resume(returning: ())
                } else {
                    self.log("Process failed: \(executableURL.lastPathComponent) status=\(process.terminationStatus)")
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
            log("Installer script started: \(scriptURL.path)")
        } catch {
            log("Failed to start installer script: \(error.localizedDescription)")
            throw AppUpdateError.installerLaunchFailed
        }
    }

    private func log(_ message: String) {
        NSLog("[AppUpdate] %@", message)
    }
}
