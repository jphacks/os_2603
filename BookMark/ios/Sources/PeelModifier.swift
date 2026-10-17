import SwiftUI
import UIKit
import AudioToolbox

// 付箋を指で引っ張って「剥がす」ジェスチャー + アニメーション。
//
// 使い方:
//   SomeCard()
//     .peelable { onPeel() }
//
// - ドラッグ中: 角がめくれるアニメーション
// - 閾値(120pt)を超えたら: 触覚 + 効果音 + 丸まって消える → onPeel コールバック
// - 閾値未満でリリース: 元の位置にスナップバック

private let kPeelThreshold: CGFloat = 120

struct PeelModifier: ViewModifier {
    let onPeel: () -> Void

    @State private var drag: CGSize = .zero
    @State private var isDragging = false
    @State private var peeled = false

    private let impact = UIImpactFeedbackGenerator(style: .heavy)

    private var progress: CGFloat {
        let dist = hypot(drag.width, drag.height)
        return min(dist / kPeelThreshold, 1.0)
    }

    func body(content: Content) -> some View {
        content
            // コーナーめくれオーバーレイ
            .overlay(alignment: .bottomTrailing) {
                if isDragging && progress > 0.05 {
                    CornerPeelShape(progress: progress)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color(white: 0.85).opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.18 * progress), radius: 4, x: -2, y: -2)
                        .allowsHitTesting(false)
                }
            }
            .offset(drag)
            .rotationEffect(.degrees(Double(drag.width) * 0.08))
            .shadow(radius: isDragging ? 10 * progress : 0,
                    x: drag.width * 0.1, y: drag.height * 0.1)
            // 剥がれアニメーション: 丸まって小さくなって消える
            .scaleEffect(peeled ? 0.05 : 1)
            .opacity(peeled ? 0 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: peeled)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in
                        if !isDragging {
                            impact.prepare()
                            isDragging = true
                        }
                        withAnimation(.interactiveSpring(response: 0.25)) {
                            drag = v.translation
                        }
                    }
                    .onEnded { v in
                        let dist = hypot(v.translation.width, v.translation.height)
                        if dist >= kPeelThreshold {
                            triggerPeel()
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                                drag = .zero
                                isDragging = false
                            }
                        }
                    }
            )
    }

    private func triggerPeel() {
        impact.impactOccurred()
        AudioServicesPlaySystemSound(1519) // "Peek" system sound
        withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
            peeled = true
            isDragging = false
        }
        // アニメーション完了後にコールバック
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            onPeel()
        }
    }
}

// コーナーがめくれて見える三角形（右下コーナー）
private struct CornerPeelShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height) * progress
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX,       y: rect.maxY - size))
        p.addLine(to: CGPoint(x: rect.maxX - size, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX,        y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

extension View {
    func peelable(onPeel: @escaping () -> Void) -> some View {
        modifier(PeelModifier(onPeel: onPeel))
    }
}

// MARK: - 剥がした後のクイズカード

/// 付箋を剥がした後に表示する確認ステップ。
/// 「覚えた」→ onMastered（ゴミ箱ゲームへ）
/// 「まだ」→ onReturn（付箋を元に戻す）
struct PeelQuizView: View {
    let sticky: Sticky
    var onMastered: () -> Void
    var onReturn: () -> Void

    @State private var aiQuestion: String?
    @State private var loadingQuestion = false

    var body: some View {
        ZStack {
            BooksStyle.background.ignoresSafeArea()
            VStack(spacing: 0) {
                // ハンドル
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // 問題文
                        VStack(alignment: .leading, spacing: 8) {
                            Text("p.\(sticky.pageNumber) · ここ、覚えてる？")
                                .font(.footnote).bold().foregroundStyle(.secondary)

                            if loadingQuestion {
                                ProgressView("問題を生成中…")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(aiQuestion ?? "この内容、何の話でしたか？")
                                    .font(.title3).bold()
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BooksStyle.card)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(sticky.color.color)
                                .frame(width: 5).padding(.vertical, 16)
                        }

                        // ヒント（周辺の切り抜き）
                        if !sticky.clipBefore.isEmpty || !sticky.clipAfter.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ヒント").font(.caption2).foregroundStyle(.tertiary)
                                contextText
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(BooksStyle.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        // 答え
                        VStack(alignment: .leading, spacing: 6) {
                            Text(sticky.heading).font(.headline)
                            if !sticky.memo.isEmpty {
                                Text(sticky.memo).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(sticky.color.color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                        // ボタン
                        HStack(spacing: 12) {
                            Button(action: onReturn) {
                                Label("まだ", systemImage: "arrow.uturn.backward")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PeelButtonStyle(filled: false))

                            Button(action: onMastered) {
                                Label("覚えた！", systemImage: "checkmark")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PeelButtonStyle(filled: true))
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
        }
        .task { await loadQuestion() }
    }

    @ViewBuilder private var contextText: some View {
        ForEach(sticky.clipBefore, id: \.self) {
            Text($0).font(BooksStyle.serif(.caption)).foregroundStyle(.secondary)
        }
        Text(sticky.marker).font(BooksStyle.serif(.caption)).bold()
            .padding(.horizontal, 3).padding(.vertical, 1)
            .background(sticky.color.color.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        ForEach(sticky.clipAfter, id: \.self) {
            Text($0).font(BooksStyle.serif(.caption)).foregroundStyle(.secondary)
        }
    }

    private func loadQuestion() async {
        guard AIHelper.isAvailable else { return }
        loadingQuestion = true
        aiQuestion = await AIHelper.generateQuestion(
            marker: sticky.marker,
            heading: sticky.heading,
            memo: sticky.memo,
            clipBefore: sticky.clipBefore,
            clipAfter: sticky.clipAfter
        )
        loadingQuestion = false
    }
}

private struct PeelButtonStyle: ButtonStyle {
    var filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline).bold()
            .padding(.vertical, 14)
            .foregroundStyle(filled ? .white : BooksStyle.ink)
            .background(filled ? BooksStyle.ink : BooksStyle.card, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
