import AppKit
import Combine
import QuartzCore
import SwiftUI

enum IslandOverlayLayout {
    static let horizontalPadding: CGFloat = 20
    static let topPadding: CGFloat = 0
    static let bottomPadding: CGFloat = 28
    static let topMargin: CGFloat = 0
    static let topEdgeHoverTolerance: CGFloat = 8

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

    static func interactiveRect(for shellSize: CGSize, in bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.midX - (shellSize.width / 2),
            y: bounds.maxY - topPadding - shellSize.height - topEdgeHoverTolerance,
            width: shellSize.width,
            height: shellSize.height + topEdgeHoverTolerance
        )
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class TransparentContainerView: NSView {
    var interactiveRectProvider: (() -> CGRect)?

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

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveRectProvider?().contains(point) ?? true else {
            return nil
        }

        return super.hitTest(point)
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
    private let settingsStore: SettingsConfigStore
    private var panel: IslandPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var mousePassthroughTimer: Timer?
    private var globalMouseDownMonitor: Any?

    init(sessionController: CodexSessionController, settingsStore: SettingsConfigStore) {
        self.sessionController = sessionController
        self.settingsStore = settingsStore
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
        startMousePassthroughMonitor()
        startOutsideClickMonitor()
        panel.orderFrontRegardless()
    }

    private func makeContentView() -> NSView {
        let containerView = TransparentContainerView(frame: .zero)
        containerView.interactiveRectProvider = { [weak self, weak containerView] in
            guard let self, let containerView else {
                return .zero
            }

            let shellSize = IslandShellStyle.forState(self.islandController.presentationState).size
            return IslandOverlayLayout.interactiveRect(for: shellSize, in: containerView.bounds)
        }
        let hostingView = TransparentHostingView(
            rootView: ContentView(controller: islandController)
                .environmentObject(sessionController)
                .environmentObject(settingsStore)
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

        updateMousePassthrough()
    }

    private func startMousePassthroughMonitor() {
        mousePassthroughTimer?.invalidate()
        mousePassthroughTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMousePassthrough()
            }
        }
        RunLoop.main.add(mousePassthroughTimer!, forMode: .common)
        updateMousePassthrough()
    }

    private func startOutsideClickMonitor() {
        guard globalMouseDownMonitor == nil else { return }

        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleGlobalMouseDown()
            }
        }
    }

    private func handleGlobalMouseDown() {
        guard let panel else { return }
        guard let contentBounds = panel.contentView?.bounds else { return }

        let mouseLocation = NSEvent.mouseLocation
        let localPoint = panel.convertPoint(fromScreen: mouseLocation)
        let shellSize = IslandShellStyle.forState(islandController.presentationState).size
        let interactiveRect = IslandOverlayLayout.interactiveRect(for: shellSize, in: contentBounds)

        guard !interactiveRect.contains(localPoint) else {
            return
        }

        islandController.handleOutsideInteraction()
    }

    private func updateMousePassthrough() {
        guard let panel else { return }
        guard let contentBounds = panel.contentView?.bounds else { return }

        let mouseLocation = NSEvent.mouseLocation
        let localPoint = panel.convertPoint(fromScreen: mouseLocation)
        let shellSize = IslandShellStyle.forState(islandController.presentationState).size
        let interactiveRect = IslandOverlayLayout.interactiveRect(for: shellSize, in: contentBounds)
        panel.ignoresMouseEvents = !interactiveRect.contains(localPoint)
    }

    deinit {
        mousePassthroughTimer?.invalidate()
        if let globalMouseDownMonitor {
            NSEvent.removeMonitor(globalMouseDownMonitor)
        }
    }
}
