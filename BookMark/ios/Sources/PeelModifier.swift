import SwiftUI
import UIKit

// 付箋を長押し（0.15秒）→ 左右にスワイプして「剥がす」ジェスチャー。
//
// 使い方:
//   StickyRow(sticky: s)
//       .peelable(tint: s.color.color) { markMastered(s) }
//
// スワイプ方向の反対側が軸になり、カードがめくれるように持ち上がる。
// 剥がれたら上に飛んでいく。

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
            LongPressGesture(minimumDuration: 0.15)
                .onEnded { _ in paper.impactOccurred(intensity: 0.3) }
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    if case .second(true, let drag?) = value { changed(drag) }
                }
                .onEnded { value in
                    if case .second(true, _) = value { ended() }
                }
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

    private func changed(_ v: DragGesture.Value) {
        if side == nil {
            guard abs(v.translation.width) > 6 else { return }
            // スワイプ方向の反対の side を割り当て → スワイプ先が軸になる
            side = v.translation.width > 0 ? .left : .right
            glue.prepare(); snap.prepare()
        }
        pull = max(0, v.translation.width * dir)
        sway = v.translation.height
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
