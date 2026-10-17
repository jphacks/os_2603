import SwiftUI

// 復習モード: AI 問題 or 簡易カード。答え確認後にその場で覚えた登録ができる。

struct ReviewView: View {
    let stickies: [Sticky]
    var onMastered: (Sticky) -> Void
    var onClose: () -> Void

    @State private var deck: [Sticky] = []
    @State private var index = 0
    @State private var showAnswer = false
    @State private var undoTarget: Sticky?
    @State private var showUndo = false

    var body: some View {
        ZStack {
            BooksStyle.background.ignoresSafeArea()
            VStack {
                HStack {
                    BooksCloseButton { onClose() }
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
                .buttonStyle(CaptureButton()).frame(width: 160)
            }
        } else {
            ReviewCard(
                sticky: deck[index],
                showAnswer: $showAnswer,
                onNext: { showAnswer = false; index += 1 },
                onMastered: { markMastered(deck[index]) }
            )
        }
    }

    private func markMastered(_ sticky: Sticky) {
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
                Text("覚えました")
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
            .foregroundStyle(.white)
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
    var onMastered: () -> Void
    @Environment(VaultManager.self) private var vault

    @State private var aiQuestion: String?
    @State private var loadingQuestion = false

    private var displayMemo: String {
        if let data = sticky.encryptedMemo { return vault.decrypt(data) ?? "" }
        return sticky.memo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("p.\(sticky.pageNumber) · \(questionText)")
                .font(.headline).foregroundStyle(BooksStyle.ink)

            contextView

            if showAnswer {
                Divider().padding(.vertical, 2)
                Text(sticky.heading).font(.headline)
                if !displayMemo.isEmpty {
                    Text(displayMemo).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                if showAnswer {
                    Button { onNext() } label: { Text("次へ").frame(maxWidth: .infinity) }
                        .buttonStyle(CaptureButton())
                    Button {
                        onMastered()
                    } label: {
                        Label("覚えた", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CaptureButton(ghost: true))
                } else {
                    Button {
                        showAnswer = true
                    } label: {
                        Text(loadingQuestion ? "問題生成中…" : "答えを見る").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CaptureButton())
                    .disabled(loadingQuestion)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BooksStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
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
        .font(BooksStyle.serif(.body)).lineSpacing(6)
    }

    private func loadQuestion() async {
        guard AIHelper.isAvailable else { return }
        loadingQuestion = true
        aiQuestion = await AIHelper.generateQuestion(
            marker: sticky.marker,
            heading: sticky.heading,
            memo: displayMemo,
            clipBefore: sticky.clipBefore,
            clipAfter: sticky.clipAfter)
        loadingQuestion = false
    }
}
