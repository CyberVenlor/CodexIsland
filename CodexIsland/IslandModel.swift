import AppKit
import SwiftUI

enum CollapsedIslandMode: String, CaseIterable, Identifiable {
    case detailed
    case simplified

    var id: Self { self }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .detailed:
            language.label(english: "Detailed", chinese: "详细")
        case .simplified:
            language.label(english: "Simplified", chinese: "简洁")
        }
    }
}

enum IslandPresentationState: Equatable {
    case collapsed(CollapsedIslandMode)
    case expanded(ExpandedIslandPanel)
}

enum ExpandedIslandPanel: Equatable {
    case sessions
    case settings
    case approval(status: ApprovalPanelStatus)
    case sessionEnded
    case sessionSuspicious
}

enum ApprovalPanelStatus: Equatable {
    case pending
    case completed
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
    private static let approvalCompletionDisplayDuration: TimeInterval = 1.8

    @Published var collapsedMode: CollapsedIslandMode = .detailed
    @Published private(set) var isExpanded = false
    @Published private(set) var activePanel: ExpandedIslandPanel = .sessions

    private var pendingCollapse: DispatchWorkItem?
    private var pendingTransition: DispatchWorkItem?
    private var pendingApprovalCompletion: DispatchWorkItem?
    private var pendingSessionEndedDismissal: DispatchWorkItem?
    private var lastTransitionAt: Date = .distantPast
    private var targetExpandedState = false
    private var approvalPresentationLocked = false
    private var transientPresentationLocked = false
    private var transientPresentationRequiresInteraction = false
    private var transientHoverArmed = false
    private var sessionEndedDisplayDuration: TimeInterval = 2
    private var suspiciousSessionDisplayDuration: TimeInterval = 2

    let items: [IslandListItem] = [
        IslandListItem(title: "Now Playing", subtitle: "Ambient mix queued for focus mode", systemImage: "music.note"),
        IslandListItem(title: "Build Ready", subtitle: "CodexIsland.app compiled successfully", systemImage: "hammer.fill"),
        IslandListItem(title: "Sync Status", subtitle: "Branch is clean and ready to push", systemImage: "arrow.triangle.branch")
    ]

    var presentationState: IslandPresentationState {
        if isExpanded {
            .expanded(activePanel)
        } else {
            .collapsed(collapsedMode)
        }
    }

    func updateTransientPresentationSettings(
        sessionEndedDuration: TimeInterval,
        suspiciousDuration: TimeInterval
    ) {
        sessionEndedDisplayDuration = max(0, sessionEndedDuration)
        suspiciousSessionDisplayDuration = max(0, suspiciousDuration)
    }

    func handleHoverChange(_ isHovering: Bool) {
        guard !approvalPresentationLocked else { return }

        if transientPresentationLocked {
            guard transientPresentationRequiresInteraction else { return }

            if isHovering {
                transientHoverArmed = true
                return
            }

            guard transientHoverArmed else { return }
            dismissTransientPresentation()
            return
        }

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

    func collapse(resetActivePanel: Bool = true) {
        guard isExpanded else { return }
        guard !approvalPresentationLocked, !transientPresentationLocked else { return }
        guard canTransitionNow else {
            scheduleTransitionRetry(for: false)
            return
        }

        withAnimation(Self.collapseAnimation) {
            isExpanded = false
            if resetActivePanel {
                activePanel = .sessions
            }
        }
        lastTransitionAt = Date()
    }

    func toggleSettingsPanel() {
        guard isExpanded, !approvalPresentationLocked, !transientPresentationLocked else { return }

        withAnimation(Self.expandAnimation) {
            activePanel = activePanel == .settings ? .sessions : .settings
        }
    }

    func updateApprovalPresentation(hasPendingApproval: Bool) {
        pendingSessionEndedDismissal?.cancel()
        pendingSessionEndedDismissal = nil
        transientPresentationLocked = false

        pendingApprovalCompletion?.cancel()
        pendingApprovalCompletion = nil

        if hasPendingApproval {
            guard approvalPresentationLocked || !isExpanded else { return }
            approvalPresentationLocked = true
            targetExpandedState = true
            if !isExpanded {
                expand()
            }
            withAnimation(Self.expandAnimation) {
                activePanel = .approval(status: .pending)
            }
            return
        }

        guard approvalPresentationLocked else { return }

        withAnimation(Self.expandAnimation) {
            activePanel = .approval(status: .completed)
        }
        Self.performApprovalCompletionHaptic()

        let completionWorkItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.approvalPresentationLocked = false
                self.targetExpandedState = false
                self.collapse(resetActivePanel: false)
                self.activePanel = .sessions
            }
        }

        pendingApprovalCompletion = completionWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.approvalCompletionDisplayDuration,
            execute: completionWorkItem
        )
    }

    func presentSessionEndedPanel() {
        guard !approvalPresentationLocked else { return }
        guard !isExpanded else { return }

        presentTransientPanel(.sessionEnded, displayDuration: sessionEndedDisplayDuration)
    }

    func presentSuspiciousSessionPanel() {
        guard !approvalPresentationLocked else { return }
        guard !isExpanded else { return }

        presentTransientPanel(.sessionSuspicious, displayDuration: suspiciousSessionDisplayDuration)
    }

    func handleOutsideInteraction() {
        guard transientPresentationLocked, transientPresentationRequiresInteraction else { return }
        dismissTransientPresentation()
    }

    private func presentTransientPanel(_ panel: ExpandedIslandPanel, displayDuration: TimeInterval) {
        pendingSessionEndedDismissal?.cancel()
        pendingSessionEndedDismissal = nil
        transientPresentationLocked = true
        transientPresentationRequiresInteraction = displayDuration == 0
        transientHoverArmed = false
        targetExpandedState = true

        expand()
        withAnimation(Self.expandAnimation) {
            activePanel = panel
        }

        guard displayDuration > 0 else {
            return
        }

        let dismissWorkItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.dismissTransientPresentation()
            }
        }

        pendingSessionEndedDismissal = dismissWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + displayDuration,
            execute: dismissWorkItem
        )
    }

    private func dismissTransientPresentation() {
        pendingSessionEndedDismissal?.cancel()
        pendingSessionEndedDismissal = nil
        transientPresentationLocked = false
        transientPresentationRequiresInteraction = false
        transientHoverArmed = false
        targetExpandedState = false
        collapse(resetActivePanel: false)
        activePanel = .sessions
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

    private static func performApprovalCompletionHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
