import SwiftUI

struct IslandShellStyle: Equatable {
    let size: CGSize
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    let backgroundOpacity: Double
    let strokeOpacity: Double
    let shadowOpacity: Double

    static func forState(_ state: IslandPresentationState, approvalPanelShowsDenyReason: Bool = false) -> IslandShellStyle {
        switch state {
        case .collapsed(.detailed):
            IslandShellStyle(
                size: CGSize(width: 240, height: 32),
                topRadius: 6,
                bottomRadius: 12,
                backgroundOpacity: 1.0,
                strokeOpacity: 0.18,
                shadowOpacity: 0.20
            )
        case .collapsed(.simplified):
            IslandShellStyle(
                size: CGSize(width: 208, height: 32),
                topRadius: 14,
                bottomRadius: 20,
                backgroundOpacity: 1.0,
                strokeOpacity: 0.72,
                shadowOpacity: 0.10
            )
        case .expanded(.sessions):
            IslandShellStyle(
                size: CGSize(width: 420, height: 480),
                topRadius: 8,
                bottomRadius: 20,
                backgroundOpacity: 1.0,
                strokeOpacity: 0.12,
                shadowOpacity: 0.26
            )
        case .expanded(.approval(_)):
            IslandShellStyle(
                size: CGSize(width: 440, height: approvalPanelShowsDenyReason ? 370 : 270),
                topRadius: 8,
                bottomRadius: 20,
                backgroundOpacity: 1.0,
                strokeOpacity: 0.14,
                shadowOpacity: 0.24
            )
        case .expanded(.sessionEnded):
            IslandShellStyle(
                size: CGSize(width: 420, height: 176),
                topRadius: 8,
                bottomRadius: 20,
                backgroundOpacity: 1.0,
                strokeOpacity: 0.14,
                shadowOpacity: 0.22
            )
        case .expanded(.sessionSuspicious):
            IslandShellStyle(
                size: CGSize(width: 420, height: 176),
                topRadius: 8,
                bottomRadius: 20,
                backgroundOpacity: 1.0,
                strokeOpacity: 0.14,
                shadowOpacity: 0.22
            )
        case .expanded(.settings):
            IslandShellStyle(
                size: CGSize(width: 560, height: 420),
                topRadius: 8,
                bottomRadius: 22,
                backgroundOpacity: 1.0,
                strokeOpacity: 0.12,
                shadowOpacity: 0.28
            )
        }
    }

    static let maximumSize = CGSize(width: 560, height: 700)
    static let overshootWidth: CGFloat = 32
    static let overshootHeight: CGFloat = 36
    static let minimumBottomY: CGFloat = 32
    static let canvasSize = CGSize(
        width: maximumSize.width + overshootWidth,
        height: maximumSize.height + overshootHeight
    )
}

struct AnimatedNotchShape: Shape {
    private let topExtension: CGFloat = 1.2
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
        let bottomY = max(shellRect.maxY, IslandShellStyle.minimumBottomY)

        let top = min(max(0, topRadius), min(shellRect.width, shellRect.height) / 2)
        let bottom = min(max(0, bottomRadius), min(shellRect.width, shellRect.height) / 2)
        let extendedTopY = shellRect.minY - topExtension

        var path = Path()

        // Add a thin top cap so the visible stroke sits slightly above the shell.
        path.move(to: CGPoint(x: shellRect.minX - top, y: shellRect.minY))
        path.addLine(to: CGPoint(x: shellRect.minX - top, y: extendedTopY))
        path.addLine(to: CGPoint(x: shellRect.maxX + top, y: extendedTopY))
        path.addLine(to: CGPoint(x: shellRect.maxX + top, y: shellRect.minY))

        // Top-right corner.
        path.addQuadCurve(
            to: CGPoint(x: shellRect.maxX, y: shellRect.minY + top),
            control: CGPoint(x: shellRect.maxX, y: shellRect.minY)
        )

        // Right edge.
        path.addLine(to: CGPoint(x: shellRect.maxX, y: bottomY - bottom))

        // Bottom-right corner.
        path.addQuadCurve(
            to: CGPoint(x: shellRect.maxX - bottom, y: bottomY),
            control: CGPoint(x: shellRect.maxX, y: bottomY)
        )

        // Bottom edge.
        path.addLine(to: CGPoint(x: shellRect.minX + bottom, y: bottomY))

        // Bottom-left corner.
        path.addQuadCurve(
            to: CGPoint(x: shellRect.minX, y: bottomY - bottom),
            control: CGPoint(x: shellRect.minX, y: bottomY)
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
