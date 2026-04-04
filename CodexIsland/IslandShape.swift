import SwiftUI

struct IslandShellStyle: Equatable {
    let size: CGSize
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    let shoulderInset: CGFloat
    let shoulderDepth: CGFloat
    let backgroundOpacity: Double
    let strokeOpacity: Double
    let shadowOpacity: Double

    static func forState(_ state: IslandPresentationState) -> IslandShellStyle {
        switch state {
        case .collapsed(.detailed):
            IslandShellStyle(
                size: CGSize(width: 294, height: 70),
                topCornerRadius: 12,
                bottomCornerRadius: 24,
                shoulderInset: 0,
                shoulderDepth: 0,
                backgroundOpacity: 0.98,
                strokeOpacity: 0.18,
                shadowOpacity: 0.20
            )
        case .collapsed(.simplified):
            IslandShellStyle(
                size: CGSize(width: 226, height: 54),
                topCornerRadius: 10,
                bottomCornerRadius: 20,
                shoulderInset: 0,
                shoulderDepth: 0,
                backgroundOpacity: 0.05,
                strokeOpacity: 0.72,
                shadowOpacity: 0.10
            )
        case .expanded:
            IslandShellStyle(
                size: CGSize(width: 336, height: 248),
                topCornerRadius: 14,
                bottomCornerRadius: 34,
                shoulderInset: 28,
                shoulderDepth: 44,
                backgroundOpacity: 0.98,
                strokeOpacity: 0.12,
                shadowOpacity: 0.26
            )
        }
    }
}

struct AnimatedNotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var shoulderInset: CGFloat
    var shoulderDepth: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(topCornerRadius, bottomCornerRadius),
                AnimatablePair(shoulderInset, shoulderDepth)
            )
        }
        set {
            topCornerRadius = newValue.first.first
            bottomCornerRadius = newValue.first.second
            shoulderInset = newValue.second.first
            shoulderDepth = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let topRadius = min(topCornerRadius, rect.width / 2, rect.height / 2)
        let bottomRadius = min(bottomCornerRadius, rect.width / 2, rect.height / 2)
        let inset = min(max(0, shoulderInset), rect.width / 2 - topRadius)
        let depth = min(max(0, shoulderDepth), rect.height - bottomRadius - topRadius)
        let topLeftX = rect.minX + inset
        let topRightX = rect.maxX - inset
        let shoulderY = rect.minY + topRadius + depth

        var path = Path()

        path.move(to: CGPoint(x: topLeftX + topRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: topRightX - topRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: topRightX, y: rect.minY + topRadius),
            control: CGPoint(x: topRightX, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: shoulderY),
            control1: CGPoint(x: topRightX, y: rect.minY + topRadius + depth * 0.32),
            control2: CGPoint(x: rect.maxX, y: rect.minY + topRadius + depth * 0.72)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: shoulderY))
        path.addCurve(
            to: CGPoint(x: topLeftX, y: rect.minY + topRadius),
            control1: CGPoint(x: rect.minX, y: rect.minY + topRadius + depth * 0.72),
            control2: CGPoint(x: topLeftX, y: rect.minY + topRadius + depth * 0.32)
        )
        path.addQuadCurve(
            to: CGPoint(x: topLeftX + topRadius, y: rect.minY),
            control: CGPoint(x: topLeftX, y: rect.minY)
        )

        return path
    }
}
