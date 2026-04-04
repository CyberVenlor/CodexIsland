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
        .frame(width: shellStyle.size.width, height: shellStyle.size.height)
        .contentShape(Rectangle())
        .onHover { isHovering in
            if isHovering {
                controller.expand()
            } else {
                controller.collapse()
            }
        }
        .animation(IslandController.animation, value: state)
    }

    private var shell: some View {
        AnimatedNotchShape(
            topCornerRadius: shellStyle.topCornerRadius,
            bottomCornerRadius: shellStyle.bottomCornerRadius
        )
        .fill(.black.opacity(shellStyle.backgroundOpacity))
        .overlay {
            AnimatedNotchShape(
                topCornerRadius: shellStyle.topCornerRadius,
                bottomCornerRadius: shellStyle.bottomCornerRadius
            )
            .stroke(Color.white.opacity(shellStyle.strokeOpacity), lineWidth: 1.2)
        }
        .shadow(color: .black.opacity(shellStyle.shadowOpacity), radius: 26, y: 18)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .collapsed(.detailed):
            CollapsedDetailedIslandView()
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .collapsed(.simplified):
            CollapsedSimplifiedIslandView()
                .transition(.opacity)
        case .expanded:
            ExpandedIslandView(items: controller.items)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
}

struct CollapsedDetailedIslandView: View {
    var body: some View {
        HStack(spacing: 14) {
            IslandArtworkView()

            VStack(alignment: .leading, spacing: 3) {
                Text("Playback Ready")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Ambient mix queued for focus mode")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "waveform")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CollapsedSimplifiedIslandView: View {
    var body: some View {
        Color.clear
    }
}

struct ExpandedIslandView: View {
    let items: [IslandListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Dynamic Island")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.bottom, 14)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                IslandListRow(item: item)

                if index < items.count - 1 {
                    Divider()
                        .overlay(.white.opacity(0.08))
                        .padding(.vertical, 8)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .frame(width: 44, height: 44)
    }
}
