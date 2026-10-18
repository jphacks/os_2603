import SwiftUI
import UIKit

// 付箋を長押し（0.3秒）→ 左右にスワイプして「剥がす」ジェスチャー。
//
// 使い方:
//   StickyRow(sticky: s)
//       .peelable(tint: s.color.color) { markMastered(s) }
//
// UIGestureRecognizerRepresentable (iOS 18+) で UIKit の
// UILongPressGestureRecognizer を使い、ScrollView との競合を解消。
// 長押し成立前に指が動いた場合は ScrollView にタッチが渡る。

// MARK: - UIKit ジェスチャブリッジ

struct PeelPressGesture: UIGestureRecognizerRepresentable {
    var minimumDuration: TimeInterval = 0.3
    var onBegan: () -> Void
    var onChanged: (CGSize) -> Void
    var onEnded: () -> Void

    final class Coordinator { var start: CGPoint = .zero }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let g = UILongPressGestureRecognizer()
        g.minimumPressDuration = minimumDuration
        g.allowableMovement = 10
        return g
    }

    func handleUIGestureRecognizerAction(_ g: UILongPressGestureRecognizer, context: Context) {
        let p = g.location(in: nil)
        switch g.state {
        case .began:
            context.coordinator.start = p
            onBegan()
        case .changed:
            let s = context.coordinator.start
            onChanged(CGSize(width: p.x - s.x, height: p.y - s.y))
        case .ended, .cancelled:
            onEnded()
        default:
            break
        }
    }
}

// MARK: - PeelableSticky

struct PeelableSticky<Content: View>: View {
    let tint: Color
    let onPeeled: () -> Void
    @ViewBuilder let content: Content

    private enum Side { case right, left }

    @State private var side: Side? = nil
    @State private var pull: CGFloat = 0
    @State private var sway: CGFloat = 0
    @State private var released = false
    @State private var gone = false
    @State private var lastTick: CGFloat = 0
    @State private var verticalIntent = false

    private let liftEnd: CGFloat = 60
    private let glueEnd: CGFloat = 130
    private let glueBand: CGFloat = 0.3

    private let paper = UIImpactFeedbackGenerator(style: .soft)
    private let glue  = UIImpactFeedbackGenerator(style: .rigid)
    private let snap  = UIImpactFeedbackGenerator(style: .heavy)

    // スワイプ方向 → side を逆に割り当てることで、
    // スワイプ先の辺が軸（のり）になる
    private var dir: CGFloat { side == .left ? 1 : -1 }
    private var glueAlign: Alignment { side == .left ? .trailing : .leading }
    private var freeAlign: Alignment { side == .left ? .leading : .trailing }
    private var freeEdge: UnitPoint { side == .left ? .leading : .trailing }

    private var lift: CGFloat { min(pull / liftEnd, 1) }
    private var glueProgress: CGFloat {
        max(0, min((pull - liftEnd) / (glueEnd - liftEnd), 1))
    }

    private var peelLine: CGFloat { released ? 0 : glueBand * (1 - glueProgress) }

    private var hinge: UnitPoint {
        UnitPoint(x: side == .left ? 1 - peelLine : peelLine, y: 0.5)
    }

    private var angle: Double {
        released ? 25 : Double(50 * lift + 15 * glueProgress)
    }

    var body: some View {
        ZStack(alignment: side == .left ? .trailing : .leading) {
            if side == nil {
                content
            } else {
                // 貼り付き側（軸側）：変形しない
                content
                    .mask { band(peelLine + 0.005, align: glueAlign) }
                    .opacity(gone ? 0 : 1)

                // 浮いた側：剥がれ目を軸にめくれる
                content
                    .overlay(
                        LinearGradient(colors: [.white.opacity(0.25 * lift),
                                                .black.opacity(0.22 * lift)],
                                       startPoint: hinge, endPoint: freeEdge)
                            .allowsHitTesting(false)
                    )
                    .mask { band(1 - peelLine, align: freeAlign) }
                    .rotation3DEffect(.degrees(angle * Double(dir)), axis: (0, 1, 0),
                                      anchor: hinge, perspective: 0.5)
                    .shadow(color: .black.opacity(0.08 + 0.2 * lift),
                            radius: 2 + 10 * lift, x: dir * (2 + 6 * lift), y: 4)
                    .offset(x: gone ? dir * 80 : (released ? dir * (pull - glueEnd) : 0),
                            y: gone ? -600 : (released ? sway : 0))
                    .rotationEffect(.degrees(gone ? Double(dir) * -15 : (released ? Double(sway) / 6 : 0)))
                    .opacity(gone ? 0 : 1)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(tint.opacity(0.25))
                .mask { band(glueBand, align: glueAlign) }
                .opacity(side == nil ? 0 : 1)
        }
        .gesture(
            PeelPressGesture(
                onBegan:   { paper.impactOccurred(intensity: 0.3) },
                onChanged: { t in changed(t) },
                onEnded:   { ended() }
            )
        )
        .allowsHitTesting(!gone)
    }

    private func band(_ fraction: CGFloat, align: Alignment) -> some View {
        GeometryReader { g in
            Rectangle()
                .frame(width: max(0, g.size.width * fraction))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align)
        }
    }

    private func changed(_ t: CGSize) {
        if side == nil && !verticalIntent {
            guard max(abs(t.width), abs(t.height)) > 8 else { return }
            if abs(t.height) > abs(t.width) {
                verticalIntent = true
                return
            }
            side = t.width > 0 ? .left : .right
            glue.prepare(); snap.prepare()
        }
        guard !verticalIntent else { return }

        pull = max(0, t.width * dir)
        sway = t.height
        tickHaptics()

        if !released && pull >= glueEnd {
            snap.impactOccurred(intensity: 1)
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                released = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                paper.impactOccurred(intensity: 0.4)
            }
        }
    }

    private func ended() {
        if verticalIntent {
            verticalIntent = false
            return
        }
        if released {
            withAnimation(.easeIn(duration: 0.3)) { gone = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onPeeled() }
        } else {
            paper.impactOccurred(intensity: 0.5)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                pull = 0; sway = 0
            } completion: {
                side = nil
                lastTick = 0
            }
        }
    }

    private func tickHaptics() {
        guard !released else { return }
        if pull < lastTick { lastTick = pull; return }
        let inGlue = pull >= liftEnd
        let spacing: CGFloat = inGlue ? 10 - 6 * glueProgress : 18
        guard pull - lastTick >= spacing else { return }
        if inGlue {
            glue.impactOccurred(intensity: 0.4 + 0.6 * glueProgress)
        } else {
            paper.impactOccurred(intensity: 0.2)
        }
        lastTick = pull
    }
}

extension View {
    func peelable(tint: Color, onPeel: @escaping () -> Void) -> some View {
        PeelableSticky(tint: tint, onPeeled: onPeel) { self }
    }
}
