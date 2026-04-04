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
    static let animation = Animation.spring(response: 0.52, dampingFraction: 0.84)
    private static let hoverExitDelay: TimeInterval = 0.16

    @Published var collapsedMode: CollapsedIslandMode = .detailed
    @Published private(set) var isExpanded = false

    private var pendingCollapse: DispatchWorkItem?

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

        if isHovering {
            expand()
            return
        }

        let collapseWorkItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.collapse()
            }
        }

        pendingCollapse = collapseWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverExitDelay, execute: collapseWorkItem)
    }

    func expand() {
        guard !isExpanded else { return }

        withAnimation(Self.animation) {
            isExpanded = true
        }
    }

    func collapse() {
        guard isExpanded else { return }

        withAnimation(Self.animation) {
            isExpanded = false
        }
    }
}
