import AppKit
import Foundation

enum SpriteLoopState: String {
    case sleep
    case idle
}

struct SpriteAnimationManifest: Decodable {
    let frameWidth: Int
    let frameHeight: Int
    let displayScale: Double
    let animations: [SpriteAnimationManifestEntry]
}

struct SpriteAnimationManifestEntry: Decodable {
    let name: String
    let file: String
    let asset: String?
    let frames: Int
    let fps: Double?
    let loop: Bool
    let from: String?
    let to: String?
}

struct SpriteAnimationClip {
    let name: String
    let frames: [CGImage]
    let framesPerSecond: Double
    let loop: Bool
    let from: SpriteLoopState?
    let to: SpriteLoopState?
}

final class SpriteAnimationCatalog {
    static let shared = SpriteAnimationCatalog()

    let frameSize: CGSize
    let displayScale: CGFloat

    private let clipsByName: [String: SpriteAnimationClip]
    private let transitions: [TransitionKey: SpriteAnimationClip]

    private struct TransitionKey: Hashable {
        let from: SpriteLoopState
        let to: SpriteLoopState
    }

    private init() {
        let manifest = Self.loadManifest() ?? Self.fallbackManifest()

        frameSize = CGSize(width: manifest.frameWidth, height: manifest.frameHeight)
        displayScale = CGFloat(manifest.displayScale)

        var clips: [String: SpriteAnimationClip] = [:]
        var transitionClips: [TransitionKey: SpriteAnimationClip] = [:]

        for entry in manifest.animations {
            guard
                let sourceImage = Self.loadImage(for: entry),
                let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else {
                NSLog("Failed to load sprite animation image %@", entry.file)
                continue
            }

            let frames = Self.sliceFrames(
                from: cgImage,
                frameWidth: manifest.frameWidth,
                frameHeight: manifest.frameHeight,
                frameCount: entry.frames
            )

            let fromState = entry.from.flatMap(SpriteLoopState.init(rawValue:))
            let toState = entry.to.flatMap(SpriteLoopState.init(rawValue:))
            let clip = SpriteAnimationClip(
                name: entry.name,
                frames: frames,
                framesPerSecond: entry.fps ?? 12,
                loop: entry.loop,
                from: fromState,
                to: toState
            )

            clips[entry.name] = clip

            if let fromState, let toState {
                transitionClips[TransitionKey(from: fromState, to: toState)] = clip
            }
        }

        clipsByName = clips
        transitions = transitionClips
    }

    func loopClip(for state: SpriteLoopState) -> SpriteAnimationClip? {
        clipsByName[state.rawValue]
    }

    func transitionClip(from: SpriteLoopState, to: SpriteLoopState) -> SpriteAnimationClip? {
        transitions[TransitionKey(from: from, to: to)]
    }

    func transitionDuration(from: SpriteLoopState, to: SpriteLoopState) -> TimeInterval {
        guard let clip = transitionClip(from: from, to: to), !clip.frames.isEmpty else {
            return 0
        }

        return Double(clip.frames.count) / max(clip.framesPerSecond, 0.1)
    }

    private static func sliceFrames(
        from image: CGImage,
        frameWidth: Int,
        frameHeight: Int,
        frameCount: Int
    ) -> [CGImage] {
        guard frameWidth > 0, frameHeight > 0, frameCount > 0 else {
            return []
        }

        return (0..<frameCount).compactMap { index in
            let rect = CGRect(
                x: index * frameWidth,
                y: 0,
                width: frameWidth,
                height: frameHeight
            )
            return image.cropping(to: rect)
        }
    }

    private static func loadImage(for entry: SpriteAnimationManifestEntry) -> NSImage? {
        if let asset = entry.asset, let image = NSImage(named: asset) {
            return image
        }

        let basename = NSString(string: entry.file).deletingPathExtension
        if let image = NSImage(named: basename) {
            return image
        }

        guard let url = Bundle.main.url(
            forResource: basename,
            withExtension: NSString(string: entry.file).pathExtension,
            subdirectory: "Assets"
        ) else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    private static func loadManifest() -> SpriteAnimationManifest? {
        guard
            let manifestURL = Bundle.main.url(forResource: "animations", withExtension: "json", subdirectory: "Assets"),
            let manifestData = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(SpriteAnimationManifest.self, from: manifestData)
        else {
            NSLog("Failed to load sprite animation manifest from app bundle, using fallback manifest")
            return nil
        }

        return manifest
    }

    private static func fallbackManifest() -> SpriteAnimationManifest {
        SpriteAnimationManifest(
            frameWidth: 24,
            frameHeight: 16,
            displayScale: 1,
            animations: [
                SpriteAnimationManifestEntry(
                    name: "sleep",
                    file: "sleep.png",
                    asset: "sleep",
                    frames: 2,
                    fps: 3,
                    loop: true,
                    from: nil,
                    to: nil
                ),
                SpriteAnimationManifestEntry(
                    name: "idle",
                    file: "idle.png",
                    asset: "idle",
                    frames: 26,
                    fps: 12,
                    loop: true,
                    from: nil,
                    to: nil
                ),
                SpriteAnimationManifestEntry(
                    name: "idleToSleep",
                    file: "idle->sleep.png",
                    asset: "idle_to_sleep",
                    frames: 15,
                    fps: 10,
                    loop: false,
                    from: "idle",
                    to: "sleep"
                ),
                SpriteAnimationManifestEntry(
                    name: "sleepToIdle",
                    file: "sleep_to_idle.png",
                    asset: "sleep_to_idle",
                    frames: 15,
                    fps: 10,
                    loop: false,
                    from: "sleep",
                    to: "idle"
                ),
            ]
        )
    }
}
