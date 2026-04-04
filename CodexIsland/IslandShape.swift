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

    static let maximumSize = CGSize(width: 336, height: 248)
}

struct AnimatedNotchShape: Shape {
    var shellWidth: CGFloat
    var shellHeight: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(shellWidth, shellHeight),
                AnimatablePair(topRadius, bottomRadius)
            )
        }
        set {
            shellWidth = newValue.first.first
            shellHeight = newValue.first.second
            topRadius = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let width = min(max(0, shellWidth), rect.width)
        let height = min(max(0, shellHeight), rect.height)
        let shellRect = CGRect(
            x: rect.midX - (width / 2),
            y: rect.minY,
            width: width,
            height: height
        )

        let top = min(max(0, topRadius), min(shellRect.width, shellRect.height) / 2)
        let bottom = min(max(0, bottomRadius), min(shellRect.width, shellRect.height) / 2)

        var path = Path()

        // Top edge.
        path.move(to: CGPoint(x: shellRect.minX - top, y: shellRect.minY))
        path.addLine(to: CGPoint(x: shellRect.maxX + top, y: shellRect.minY))

        // Top-right corner.
        path.addQuadCurve(
            to: CGPoint(x: shellRect.maxX, y: shellRect.minY + top),
            control: CGPoint(x: shellRect.maxX, y: shellRect.minY)
        )

        // Right edge.
        path.addLine(to: CGPoint(x: shellRect.maxX, y: shellRect.maxY - bottom))

        // Bottom-right corner.
        path.addQuadCurve(
            to: CGPoint(x: shellRect.maxX - bottom, y: shellRect.maxY),
            control: CGPoint(x: shellRect.maxX, y: shellRect.maxY)
        )

        // Bottom edge.
        path.addLine(to: CGPoint(x: shellRect.minX + bottom, y: shellRect.maxY))

        // Bottom-left corner.
        path.addQuadCurve(
            to: CGPoint(x: shellRect.minX, y: shellRect.maxY - bottom),
            control: CGPoint(x: shellRect.minX, y: shellRect.maxY)
        )

        // Left edge.
        path.addLine(to: CGPoint(x: shellRect.minX, y: shellRect.minY + top))

        // Top-left corner.
        path.addQuadCurve(
            to: CGPoint(x: shellRect.minX - top, y: shellRect.minY),
            control: CGPoint(x: shellRect.minX, y: shellRect.minY)
        )

        return path
    }
}
