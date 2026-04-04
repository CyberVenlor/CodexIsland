import SwiftUI

struct IslandShellStyle: Equatable {
    let size: CGSize
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    let backgroundOpacity: Double
    let strokeOpacity: Double
    let shadowOpacity: Double

    static func forState(_ state: IslandPresentationState) -> IslandShellStyle {
        switch state {
        case .collapsed(.detailed):
            IslandShellStyle(
                size: CGSize(width: 294, height: 70),
                topRadius: 16,
                bottomRadius: 24,
                backgroundOpacity: 0.98,
                strokeOpacity: 0.18,
                shadowOpacity: 0.20
            )
        case .collapsed(.simplified):
            IslandShellStyle(
                size: CGSize(width: 226, height: 54),
                topRadius: 14,
                bottomRadius: 20,
                backgroundOpacity: 0.05,
                strokeOpacity: 0.72,
                shadowOpacity: 0.10
            )
        case .expanded:
            IslandShellStyle(
                size: CGSize(width: 336, height: 248),
                topRadius: 16,
                bottomRadius: 34,
                backgroundOpacity: 0.98,
                strokeOpacity: 0.12,
                shadowOpacity: 0.26
            )
        }
    }
}

struct AnimatedNotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(max(0, topRadius), min(rect.width, rect.height) / 2)
        let bottom = min(max(0, bottomRadius), min(rect.width, rect.height) / 2)

        var path = Path()

        // Top edge.
        path.move(to: CGPoint(x: rect.minX - top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX + top, y: rect.minY))

        // Top-right corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + top),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )

        // Right edge.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))

        // Bottom-right corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - bottom, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )

        // Bottom edge.
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))

        // Bottom-left corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottom),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )

        // Left edge.
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + top))

        // Top-left corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX - top, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )

        return path
    }
}
