import AppKit
import Combine
import QuartzCore
import SwiftUI

enum IslandOverlayLayout {
    static let horizontalPadding: CGFloat = 20
    static let topPadding: CGFloat = 0
    static let bottomPadding: CGFloat = 28
    static let topMargin: CGFloat = 0

    static let windowSize = CGSize(
        width: IslandShellStyle.canvasSize.width + (horizontalPadding * 2),
        height: IslandShellStyle.canvasSize.height + topPadding + bottomPadding
    )

    static func frameOnScreen(_ screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        let origin = CGPoint(
            x: screenFrame.midX - (windowSize.width / 2),
            y: screenFrame.maxY - windowSize.height - topMargin
        )

        return CGRect(origin: origin, size: windowSize)
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class TransparentContainerView: NSView {
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class IslandOverlayController: NSObject {
    private let islandController = IslandController()
    private let sessionController: CodexSessionController
    private var panel: IslandPanel?
    private var cancellables: Set<AnyCancellable> = []

    init(sessionController: CodexSessionController) {
        self.sessionController = sessionController
        super.init()
    }

    func start() {
        guard panel == nil else { return }

        let initialFrame = CGRect(origin: .zero, size: IslandOverlayLayout.windowSize)
        let panel = IslandPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configure(panel)
        panel.contentView = makeContentView()
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.isOpaque = false
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.superview?.wantsLayer = true
        panel.contentView?.superview?.layer?.isOpaque = false
        panel.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor
        self.panel = panel
        bindWindowUpdates()
        updateWindowFrame(animated: false)
        panel.orderFrontRegardless()
    }

    private func makeContentView() -> NSView {
        let containerView = TransparentContainerView(frame: .zero)
        let hostingView = TransparentHostingView(
            rootView: ContentView(controller: islandController)
                .environmentObject(sessionController)
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        return containerView
    }

    private func configure(_ panel: IslandPanel) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none
    }

    private func bindWindowUpdates() {
        islandController.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateWindowFrame(animated: true)
                }
            }
            .store(in: &cancellables)
    }

    private func updateWindowFrame(animated: Bool) {
        guard let panel else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let targetFrame = IslandOverlayLayout.frameOnScreen(screen)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }
}
