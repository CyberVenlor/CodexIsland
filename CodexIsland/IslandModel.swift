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
    case appUpdate
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
    private static let hapticPulseInterval: TimeInterval = 0.055

    @Published var collapsedMode: CollapsedIslandMode = .detailed
    @Published private(set) var isExpanded = false
    @Published private(set) var activePanel: ExpandedIslandPanel = .sessions
    @Published private(set) var approvalPanelShowsDenyReason = false
    @Published private(set) var updatePanelIsMandatory = false
    @Published private(set) var hoverResetToken = UUID()
    @Published private(set) var hoverResetRequiresExit = false
    @Published private(set) var approvalCompletionAnimationToken = UUID()

    private var pendingCollapse: DispatchWorkItem?
    private var pendingTransition: DispatchWorkItem?
    private var pendingApprovalCompletion: DispatchWorkItem?
    private var pendingSessionEndedDismissal: DispatchWorkItem?
    private var lastTransitionAt: Date = .distantPast
    private var targetExpandedState = false
    private var approvalPresentationLocked = false
    private var updatePresentationLocked = false
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
        guard !approvalPresentationLocked, !updatePresentationLocked else { return }

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
        guard !approvalPresentationLocked, !updatePresentationLocked, !transientPresentationLocked else { return }
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
        Self.performCollapseHaptic()
        lastTransitionAt = Date()
    }

    func toggleSettingsPanel() {
        guard isExpanded, !approvalPresentationLocked, !updatePresentationLocked, !transientPresentationLocked else { return }

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
            approvalPanelShowsDenyReason = false
            hoverResetRequiresExit = false
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
        approvalCompletionAnimationToken = UUID()

        withAnimation(Self.expandAnimation) {
            activePanel = .approval(status: .completed)
        }
        Self.performApprovalCompletionHaptic()

        let completionWorkItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.finishApprovalPresentation()
            }
        }

        pendingApprovalCompletion = completionWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.approvalCompletionDisplayDuration,
            execute: completionWorkItem
        )
    }

    func updateAppUpdatePresentation(isPresented: Bool, isMandatory: Bool) {
        guard !approvalPresentationLocked else { return }

        if isPresented {
            pendingSessionEndedDismissal?.cancel()
            pendingSessionEndedDismissal = nil
            transientPresentationLocked = false
            transientPresentationRequiresInteraction = false
            transientHoverArmed = false
            updatePresentationLocked = true
            updatePanelIsMandatory = isMandatory
            hoverResetRequiresExit = false
            targetExpandedState = true
            if !isExpanded {
                expand()
            }
            withAnimation(Self.expandAnimation) {
                activePanel = .appUpdate
            }
            return
        }

        guard updatePresentationLocked else { return }

        updatePresentationLocked = false
        updatePanelIsMandatory = false
        targetExpandedState = false
        hoverResetRequiresExit = true
        collapse(resetActivePanel: false)
        activePanel = .sessions
        hoverResetToken = UUID()
    }

    func updateApprovalPanelLayout(showsDenyReason: Bool) {
        guard approvalPresentationLocked else { return }
        guard approvalPanelShowsDenyReason != showsDenyReason else { return }

        withAnimation(Self.expandAnimation) {
            approvalPanelShowsDenyReason = showsDenyReason
        }
    }

    func presentSessionEndedPanel() {
        guard !approvalPresentationLocked, !updatePresentationLocked else { return }
        guard !isExpanded else { return }

        presentTransientPanel(
            .sessionEnded,
            displayDuration: sessionEndedDisplayDuration,
            haptic: Self.performSessionEndedHaptic
        )
    }

    func presentSuspiciousSessionPanel() {
        guard !approvalPresentationLocked, !updatePresentationLocked else { return }
        guard !isExpanded else { return }

        presentTransientPanel(
            .sessionSuspicious,
            displayDuration: suspiciousSessionDisplayDuration,
            haptic: Self.performSuspiciousSessionHaptic
        )
    }

    func handleOutsideInteraction() {
        guard transientPresentationLocked, transientPresentationRequiresInteraction else { return }
        dismissTransientPresentation()
    }

    private func presentTransientPanel(
        _ panel: ExpandedIslandPanel,
        displayDuration: TimeInterval,
        haptic: () -> Void
    ) {
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
        haptic()

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

    private func finishApprovalPresentation() {
        pendingApprovalCompletion?.cancel()
        pendingApprovalCompletion = nil
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingTransition?.cancel()
        pendingTransition = nil
        approvalPresentationLocked = false
        approvalPanelShowsDenyReason = false
        targetExpandedState = false
        hoverResetRequiresExit = true
        collapse(resetActivePanel: false)
        activePanel = .sessions
        hoverResetToken = UUID()
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
        performPrimaryTransitionHaptic()
    }

    private static func performCollapseHaptic() {
        performPrimaryTransitionHaptic()
    }

    private static func performApprovalCompletionHaptic() {
        performHapticSequence([.alignment, .alignment, .generic], interval: hapticPulseInterval)
    }

    private static func performPrimaryTransitionHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private static func performSessionEndedHaptic() {
        performHapticSequence([.alignment, .generic, .alignment], interval: hapticPulseInterval)
    }

    private static func performSuspiciousSessionHaptic() {
        performHapticSequence([.generic, .alignment, .alignment, .generic], interval: hapticPulseInterval)
    }

    private static func performHapticSequence(
        _ patterns: [NSHapticFeedbackManager.FeedbackPattern],
        interval: TimeInterval = hapticPulseInterval
    ) {
        for (index, pattern) in patterns.enumerated() {
            let delay = interval * Double(index)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
            }
        }
    }
}
