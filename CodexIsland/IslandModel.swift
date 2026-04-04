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

    @Published var collapsedMode: CollapsedIslandMode = .detailed
    @Published private(set) var isExpanded = false

    let items: [IslandListItem] = [
        IslandListItem(title: "Build Ready", subtitle: "CodexIsland.app compiled successfully", systemImage: "hammer.fill"),
        IslandListItem(title: "Review Queue", subtitle: "3 items waiting for a pass", systemImage: "text.badge.checkmark"),
        IslandListItem(title: "Sync Status", subtitle: "Branch is ahead by 1 commit", systemImage: "arrow.triangle.branch")
    ]

    var presentationState: IslandPresentationState {
        if isExpanded {
            .expanded
        } else {
            .collapsed(collapsedMode)
        }
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
