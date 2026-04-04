import SwiftUI

struct IslandShellStyle: Equatable {
    let size: CGSize
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
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
                backgroundOpacity: 0.98,
                strokeOpacity: 0.18,
                shadowOpacity: 0.18
            )
        case .collapsed(.simplified):
            IslandShellStyle(
                size: CGSize(width: 226, height: 54),
                topCornerRadius: 10,
                bottomCornerRadius: 20,
                backgroundOpacity: 0.12,
                strokeOpacity: 0.72,
                shadowOpacity: 0.10
            )
        case .expanded:
            IslandShellStyle(
                size: CGSize(width: 360, height: 248),
                topCornerRadius: 26,
                bottomCornerRadius: 34,
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

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let topRadius = min(topCornerRadius, rect.width / 2, rect.height / 2)
        let bottomRadius = min(bottomCornerRadius, rect.width / 2, rect.height / 2)

        var path = Path()

        path.move(to: CGPoint(x: rect.minX + topRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + topRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
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
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )

        return path
    }
}
