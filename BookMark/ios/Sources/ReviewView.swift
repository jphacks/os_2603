import SwiftUI

// 復習モード: AI 問題 or 簡易カード。答え確認後にその場で剥がせる。
// 剥がし→クイズ→ゴミ箱ゲームを ReviewView 内で完結させる。

struct ReviewView: View {
    let stickies: [Sticky]
    var onMastered: (Sticky) -> Void   // 覚えたが確定したとき
    var onClose: () -> Void

    @State private var deck: [Sticky] = []
    @State private var index = 0
    @State private var showAnswer = false

    // 剥がしフロー
    @State private var peelQuizSticky: Sticky?
    @State private var trashSticky: Sticky?
    @State private var undoTarget: Sticky?
    @State private var showUndo = false

    var body: some View {
        ZStack {
            Color(red: 0.969, green: 0.957, blue: 0.925).ignoresSafeArea()
            VStack {
                HStack {
                    Button("閉じる") { onClose() }
                        .font(.subheadline).bold()
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.black).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Spacer()
                    if !deck.isEmpty {
                        Text("\(min(index + 1, deck.count)) / \(deck.count)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 12)

                Spacer()
                content
                Spacer()
            }
            .overlay(alignment: .bottom) { undoToast }
        }
        .onAppear { if deck.isEmpty { deck = stickies.shuffled() } }
        .sheet(item: $peelQuizSticky) { sticky in
            PeelQuizView(
                sticky: sticky,
                onMastered: { peelQuizSticky = nil; trashSticky = sticky },
                onReturn:   { peelQuizSticky = nil }
            )
            .presentationDetents([.large])
        }
        .fullScreenCover(item: $trashSticky) { sticky in
            TrashGameView(
                sticky: sticky,
                onSuccess: { markMastered(sticky) },
                onDismiss: { trashSticky = nil; markMastered(sticky) }
            )
        }
        .animation(.spring(), value: showUndo)
    }

    @ViewBuilder private var content: some View {
        if deck.isEmpty {
            VStack(spacing: 10) {
                Text("📚").font(.system(size: 40))
                Text("復習できる付箋がまだありません").foregroundStyle(.secondary)
            }
        } else if index >= deck.count {
            VStack(spacing: 16) {
                Text("🎉").font(.system(size: 40))
                Text("今回の復習は終わりです。おつかれさま！")
                Button("もう一度") {
                    deck = stickies.shuffled(); index = 0; showAnswer = false
                }
                .buttonStyle(.borderedProminent).tint(.black)
            }
        } else {
            ReviewCard(
                sticky: deck[index],
                showAnswer: $showAnswer,
                onNext: { showAnswer = false; index += 1 },
                onPeelTapped: { peelQuizSticky = deck[index] }
            )
        }
    }

    private func markMastered(_ sticky: Sticky) {
        trashSticky = nil
        sticky.mastered = true
        sticky.masteredAt = .now
        onMastered(sticky)
        undoTarget = sticky
        withAnimation { showUndo = true }
        // 剥がした付箋はデッキから除外（次のカードへ）
        showAnswer = false
        index += 1
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            await MainActor.run { withAnimation { showUndo = false } }
        }
    }

    @ViewBuilder private var undoToast: some View {
        if showUndo, let s = undoTarget {
            HStack(spacing: 12) {
                Text("付箋を剥がしました")
                Spacer()
                Button("元に戻す") {
                    s.mastered = false; s.masteredAt = nil
                    withAnimation { showUndo = false }
                }
                .bold()
            }
            .font(.subheadline)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(.black.opacity(0.88))
            .foregroundStyle(Color(red: 0.969, green: 0.957, blue: 0.925))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16).padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - 1枚のカード（AI問題生成対応）

private struct ReviewCard: View {
    let sticky: Sticky
    @Binding var showAnswer: Bool
    var onNext: () -> Void
    var onPeelTapped: () -> Void

    @State private var aiQuestion: String?
    @State private var loadingQuestion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("p.\(sticky.pageNumber) · \(questionText)")
                .font(.footnote).bold().foregroundStyle(.secondary)

            contextView

            if showAnswer {
                Divider().padding(.vertical, 2)
                Text(sticky.heading).font(.headline)
                if !sticky.memo.isEmpty {
                    Text(sticky.memo).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                if showAnswer {
                    Button("次へ") { onNext() }
                        .buttonStyle(.borderedProminent).tint(.black)
                    Button {
                        onPeelTapped()
                    } label: {
                        Label("覚えた・剥がす", systemImage: "hand.draw")
                    }
                    .buttonStyle(.bordered).tint(sticky.color.color)
                } else {
                    Button(loadingQuestion ? "問題生成中…" : "答えを見る") {
                        showAnswer = true
                    }
                    .buttonStyle(.borderedProminent).tint(.black)
                    .disabled(loadingQuestion)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 1, green: 0.992, blue: 0.973))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black.opacity(0.08)))
        .padding(.horizontal, 16)
        .task(id: sticky.id) { await loadQuestion() }
    }

    private var questionText: String { aiQuestion ?? "ここ、何の話だった？" }

    @ViewBuilder private var contextView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let before = sticky.clipBefore.last {
                Text(before).foregroundStyle(.primary)
            }
            Text(sticky.marker).bold()
                .padding(.horizontal, 3).padding(.vertical, 1)
                .background(sticky.color.color.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            if let after = sticky.clipAfter.first {
                Text(after).foregroundStyle(.primary)
            }
        }
        .font(.body).lineSpacing(4)
    }

    private func loadQuestion() async {
        guard AIHelper.isAvailable else { return }
        loadingQuestion = true
        aiQuestion = await AIHelper.generateQuestion(
            marker: sticky.marker,
            heading: sticky.heading,
            memo: sticky.memo,
            clipBefore: sticky.clipBefore,
            clipAfter: sticky.clipAfter)
        loadingQuestion = false
    }
}
