import AppKit
import SwiftUI

enum CollapsedIslandMode: String, CaseIterable, Identifiable {
    case detailed
    case simplified

    var id: Self { self }

    var title: String {
        switch self {
        case .detailed:
            "Detailed"
        case .simplified:
            "Simplified"
        }
    }
}

enum IslandPresentationState: Equatable {
    case collapsed(CollapsedIslandMode)
    case expanded
}

struct IslandListItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
}

@MainActor
final class IslandController: ObservableObject {
    static let expandAnimation = Animation.spring(response: 0.66, dampingFraction: 0.60, blendDuration: 0.10)
    static let collapseAnimation = Animation.spring(response: 0.38, dampingFraction: 1.0)
    private static let hoverExitDelay: TimeInterval = 0.40
    private static let hoverToggleCooldown: TimeInterval = 0.24

    @Published var collapsedMode: CollapsedIslandMode = .detailed
    @Published private(set) var isExpanded = false

    private var pendingCollapse: DispatchWorkItem?
    private var pendingTransition: DispatchWorkItem?
    private var lastTransitionAt: Date = .distantPast
    private var targetExpandedState = false

    let items: [IslandListItem] = [
        IslandListItem(title: "Now Playing", subtitle: "Ambient mix queued for focus mode", systemImage: "music.note"),
        IslandListItem(title: "Build Ready", subtitle: "CodexIsland.app compiled successfully", systemImage: "hammer.fill"),
        IslandListItem(title: "Sync Status", subtitle: "Branch is clean and ready to push", systemImage: "arrow.triangle.branch")
    ]

    var presentationState: IslandPresentationState {
        if isExpanded {
            .expanded
        } else {
            .collapsed(collapsedMode)
        }
    }

    func handleHoverChange(_ isHovering: Bool) {
        pendingCollapse?.cancel()
        pendingCollapse = nil
        targetExpandedState = isHovering

        if isHovering {
            requestExpandedState(true)
            return
        }

        let collapseWorkItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.requestExpandedState(false)
            }
        }

        pendingCollapse = collapseWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverExitDelay, execute: collapseWorkItem)
    }

    func expand() {
        guard !isExpanded else { return }
        guard canTransitionNow else {
            scheduleTransitionRetry(for: true)
            return
        }

        withAnimation(Self.expandAnimation) {
            isExpanded = true
        }
        Self.performExpandHaptic()
        lastTransitionAt = Date()
    }

    func collapse() {
        guard isExpanded else { return }
        guard canTransitionNow else {
            scheduleTransitionRetry(for: false)
            return
        }

        withAnimation(Self.collapseAnimation) {
            isExpanded = false
        }
        lastTransitionAt = Date()
    }

    private var canTransitionNow: Bool {
        Date().timeIntervalSince(lastTransitionAt) >= Self.hoverToggleCooldown
    }

    private func requestExpandedState(_ shouldExpand: Bool) {
        pendingTransition?.cancel()
        pendingTransition = nil

        if shouldExpand {
            expand()
        } else {
            collapse()
        }
    }

    private func scheduleTransitionRetry(for shouldExpand: Bool) {
        pendingTransition?.cancel()

        let retryWorkItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.targetExpandedState == shouldExpand else { return }
                self.requestExpandedState(shouldExpand)
            }
        }

        pendingTransition = retryWorkItem
        let delay = max(0, Self.hoverToggleCooldown - Date().timeIntervalSince(lastTransitionAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: retryWorkItem)
    }

    private static func performExpandHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}
