import AppKit
import Combine
import QuartzCore
import SwiftUI

enum IslandOverlayLayout {
    static let horizontalPadding: CGFloat = 20
    static let topPadding: CGFloat = 0
    static let bottomPadding: CGFloat = 28
    static let topMargin: CGFloat = 0

    static func windowSize(for state: IslandPresentationState) -> CGSize {
        let shellSize = IslandShellStyle.forState(state).size

        return CGSize(
            width: shellSize.width + (horizontalPadding * 2),
            height: shellSize.height + topPadding + bottomPadding
        )
    }
}

struct IslandWindowBridge: NSViewRepresentable {
    let controller: IslandController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)

        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateController(controller)

        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window)
            context.coordinator.updateWindowFrame(animated: false)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var window: NSWindow?
        private var controller: IslandController
        private var cancellables: Set<AnyCancellable> = []
        private var boundControllerID: ObjectIdentifier

        init(controller: IslandController) {
            self.controller = controller
            self.boundControllerID = ObjectIdentifier(controller)
            super.init()
            bind(to: controller)
        }

        func updateController(_ controller: IslandController) {
            let newID = ObjectIdentifier(controller)
            guard newID != boundControllerID else { return }

            self.controller = controller
            boundControllerID = newID
            bind(to: controller)
            updateWindowFrame(animated: false)
        }

        func attach(to window: NSWindow?) {
            guard let window else { return }

            if self.window !== window {
                self.window = window
                configure(window)
            }

            updateWindowFrame(animated: false)
        }

        private func bind(to controller: IslandController) {
            cancellables.removeAll()

            controller.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.updateWindowFrame(animated: true)
                    }
                }
                .store(in: &cancellables)
        }

        private func configure(_ window: NSWindow) {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovable = false
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            window.level = .statusBar
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle
            ]

            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }

        func updateWindowFrame(animated: Bool) {
            guard let window else { return }
            guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

            let targetSize = IslandOverlayLayout.windowSize(for: controller.presentationState)
            let screenFrame = screen.frame
            let targetOrigin = CGPoint(
                x: screenFrame.midX - (targetSize.width / 2),
                y: screenFrame.maxY - targetSize.height - IslandOverlayLayout.topMargin
            )
            let targetFrame = CGRect(origin: targetOrigin, size: targetSize)

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.28
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(targetFrame, display: true)
                }
            } else {
                window.setFrame(targetFrame, display: true)
            }
        }
    }
}
