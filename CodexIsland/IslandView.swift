import SwiftUI

struct IslandView: View {
    @ObservedObject var controller: IslandController

    private var state: IslandPresentationState {
        controller.presentationState
    }

    private var shellStyle: IslandShellStyle {
        IslandShellStyle.forState(state)
    }

    private var canvasSize: CGSize {
        IslandShellStyle.maximumSize
    }

    var body: some View {
        ZStack {
            shell
            content
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .top)
        .contentShape(Rectangle())
        .onHover { isHovering in
            controller.handleHoverChange(isHovering)
        }
        .contextMenu {
            ForEach(CollapsedIslandMode.allCases) { mode in
                Button(mode.title) {
                    controller.collapsedMode = mode
                }
            }
        }
        .animation(IslandController.animation, value: state)
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
            .stroke(Color.white.opacity(shellStyle.strokeOpacity), lineWidth: 1.2)
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
        VStack(alignment: .leading, spacing: 0) {
            header(title: "Playback Ready", subtitle: "Ambient mix queued for focus mode", artworkSize: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(width: detailedSize.width, height: detailedSize.height, alignment: .top)
        .opacity(isDetailedCollapsed ? 1 : 0)
        .blur(radius: isDetailedCollapsed ? 0 : 14)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title: "Now Playing", subtitle: "Ambient mix queued for focus mode", artworkSize: 42)
            expandedDetails
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
        .opacity(isExpanded ? 1 : 0)
        .blur(radius: isExpanded ? 0 : 18)
    }

    private func header(title: String, subtitle: String, artworkSize: CGFloat) -> some View {
        HStack(spacing: 14) {
            IslandArtworkView(size: artworkSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "waveform")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 28)
        }
        .frame(height: 46, alignment: .center)
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
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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

struct IslandArtworkView: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.50, blue: 0.20),
                            Color(red: 0.92, green: 0.24, blue: 0.36)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "sparkles.tv.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
