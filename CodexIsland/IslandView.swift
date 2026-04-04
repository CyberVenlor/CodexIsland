import SwiftUI

struct IslandView: View {
    @ObservedObject var controller: IslandController
    private let shellStrokeWidth: CGFloat = 1.2

    private var state: IslandPresentationState {
        controller.presentationState
    }

    private var shellStyle: IslandShellStyle {
        IslandShellStyle.forState(state)
    }

    private var canvasSize: CGSize {
        IslandShellStyle.canvasSize
    }

    var body: some View {
        ZStack {
            islandBody
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .top)
        .contextMenu {
            ForEach(CollapsedIslandMode.allCases) { mode in
                Button(mode.title) {
                    controller.collapsedMode = mode
                }
            }
        }
    }

    private var islandBody: some View {
        ZStack {
            shell
            content
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .top)
        .overlay(alignment: .top) {
            hoverHitArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var hoverHitArea: some View {
        Color.clear
            .frame(width: shellStyle.size.width, height: shellStyle.size.height)
            .contentShape(Rectangle())
            .onHover { isHovering in
                controller.handleHoverChange(isHovering)
            }
    }

    private var shell: some View {
        AnimatedNotchShape(
            shellWidth: shellStyle.size.width,
            shellHeight: shellStyle.size.height,
            topRadius: shellStyle.topRadius,
            bottomRadius: shellStyle.bottomRadius
        )
        .fill(.black.opacity(shellStyle.backgroundOpacity))
        .overlay {
            AnimatedNotchShape(
                shellWidth: shellStyle.size.width,
                shellHeight: shellStyle.size.height,
                topRadius: shellStyle.topRadius,
                bottomRadius: shellStyle.bottomRadius
            )
            .stroke(Color.white.opacity(shellStyle.strokeOpacity), lineWidth: shellStrokeWidth)
        }
    }

    private var content: some View {
        IslandContentView(
            state: state,
            items: controller.items
        )
    }
}

struct IslandContentView: View {
    let state: IslandPresentationState
    let items: [IslandListItem]

    private let detailedSize = IslandShellStyle.forState(.collapsed(.detailed)).size
    private let expandedSize = IslandShellStyle.forState(.expanded).size

    private var isExpanded: Bool {
        if case .expanded = state {
            return true
        }
        return false
    }

    private var isDetailedCollapsed: Bool {
        if case .collapsed(.detailed) = state {
            return true
        }
        return false
    }

    var body: some View {
        ZStack(alignment: .top) {
            collapsedContent
            expandedContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .mask {
            AnimatedNotchShape(
                shellWidth: IslandShellStyle.forState(state).size.width,
                shellHeight: IslandShellStyle.forState(state).size.height,
                topRadius: IslandShellStyle.forState(state).topRadius,
                bottomRadius: IslandShellStyle.forState(state).bottomRadius
            )
        }
    }

    private var collapsedContent: some View {
        ZStack {
            Image(systemName: "waveform")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 24)
                .offset(x: -100)

            Text("W")
                .foregroundStyle(.white)
                .offset(x: 100)
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 0)
        .frame(width: detailedSize.width, height: detailedSize.height, alignment: .center)
        .opacity(isDetailedCollapsed ? 1 : 0)
        .blur(radius: isDetailedCollapsed ? 0 : 14)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            expandedDetails
        }
        .padding(.horizontal, 18)
        .padding(.top, 32)
        .padding(.bottom, 18)
        .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
        .opacity(isExpanded ? 1 : 0)
        .blur(radius: isExpanded ? 0 : 18)
    }

    @ViewBuilder
    private var expandedDetails: some View {
        let additionalItems = Array(items.dropFirst())

        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .overlay(.white.opacity(0.08))
                .padding(.top, 14)
                .padding(.bottom, 12)

            ForEach(Array(additionalItems.enumerated()), id: \.element.id) { index, item in
                IslandListRow(item: item)

                if index < additionalItems.count - 1 {
                    Divider()
                        .overlay(.white.opacity(0.08))
                        .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct IslandListRow: View {
    let item: IslandListItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
