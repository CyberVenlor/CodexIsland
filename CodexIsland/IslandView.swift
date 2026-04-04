import SwiftUI

struct IslandView: View {
    @ObservedObject var controller: IslandController

    private var state: IslandPresentationState {
        controller.presentationState
    }

    private var shellStyle: IslandShellStyle {
        IslandShellStyle.forState(state)
    }

    var body: some View {
        ZStack {
            shell
            content
        }
        .frame(width: shellStyle.size.width, height: shellStyle.size.height, alignment: .top)
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
            topRadius: shellStyle.topRadius,
            bottomRadius: shellStyle.bottomRadius
        )
        .fill(.black.opacity(shellStyle.backgroundOpacity))
        .overlay {
            AnimatedNotchShape(
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

    private var isExpanded: Bool {
        if case .expanded = state {
            return true
        }
        return false
    }

    var body: some View {
        Group {
            if case .collapsed(.simplified) = state {
                Color.clear
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    expandedDetails
                }
                .padding(.horizontal, isExpanded ? 18 : 16)
                .padding(.top, isExpanded ? 14 : 12)
                .padding(.bottom, isExpanded ? 18 : 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 14) {
            IslandArtworkView(size: isExpanded ? 42 : 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(isExpanded ? "Now Playing" : "Playback Ready")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Ambient mix queued for focus mode")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(isExpanded ? 2 : 1)
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
            if isExpanded {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(isExpanded ? 1 : 0)
        .offset(y: isExpanded ? 0 : -8)
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
