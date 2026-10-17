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
            Color(red: 0.969, green: 0.957, blue: 0.925).ignoresSafeArea()
            VStack {
                HStack {
                    Button("閉じる") { onClose() }
                        .font(.subheadline).bold()
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.black)
                        .foregroundStyle(.white)
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
                .buttonStyle(.borderedProminent).tint(.black)
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
            .font(.body).lineSpacing(4)

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
            .buttonStyle(.borderedProminent).tint(.black)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 1, green: 0.992, blue: 0.973))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black.opacity(0.08)))
        .padding(.horizontal, 16)
    }
}
