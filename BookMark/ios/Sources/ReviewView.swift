import SwiftUI

// 復習モード: 付箋の切り抜きを見て中身を思い出し、見出し・メモで答え合わせ。
// 本番ではAIが復習問題を作る想定。試作では「周辺文 → 見出し/メモ」の暗記カード。
struct ReviewView: View {
    let stickies: [Sticky]
    var onClose: () -> Void

    @State private var deck: [Sticky] = []
    @State private var index = 0
    @State private var showAnswer = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack {
                HStack {
                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 36, height: 36)
                            .background(Theme.card, in: Circle())
                    }
                    .accessibilityLabel("閉じる")
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
        }
        .onAppear { if deck.isEmpty { deck = stickies.shuffled() } }
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
                .buttonStyle(CaptureButton())
            }
        } else {
            card(deck[index])
        }
    }

    private func card(_ sticky: Sticky) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("p.\(sticky.pageNumber) ・ ここ、何の話だった？")
                .font(.footnote).bold().foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                if let before = sticky.clipBefore.last {
                    Text(before).foregroundStyle(.primary)
                }
                Text(sticky.marker)
                    .bold()
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(sticky.color.color.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                if let after = sticky.clipAfter.first {
                    Text(after).foregroundStyle(.primary)
                }
            }
            .font(Theme.serif(.body)).lineSpacing(6)

            if showAnswer {
                Divider().padding(.vertical, 2)
                Text(sticky.heading).font(.headline)
                Text(sticky.memo.isEmpty ? "（メモなし）" : sticky.memo)
                    .foregroundStyle(sticky.memo.isEmpty ? .secondary : .primary)
            }

            Button(showAnswer ? "次へ" : "答えを見る") {
                if showAnswer { showAnswer = false; index += 1 }
                else { showAnswer = true }
            }
            .buttonStyle(CaptureButton())
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }
}
