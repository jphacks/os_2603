import SwiftUI

// 復習モード: 答えを見て、もう一度 or 次へ or 付箋を剥がす。

struct ReviewView: View {
    let stickies: [Sticky]
    var onClose: () -> Void

    @State private var deck: [Sticky] = []
    @State private var index = 0
    @State private var showAnswer = false

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
        }
        .onAppear { if deck.isEmpty { deck = stickies.filter { $0.reviewEnabled }.shuffled() } }
    }

    @ViewBuilder private var content: some View {
        if deck.isEmpty {
            VStack(spacing: 10) {
                Text("📚").font(.system(size: 40))
                Text("復習対象の付箋がありません").foregroundStyle(.secondary)
                Text("付箋のメモ末尾に ? をつけると復習対象になります")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        } else if index >= deck.count {
            VStack(spacing: 16) {
                Text("🎉").font(.system(size: 40))
                Text("今回の復習おわり！")
                    .font(.title3.bold()).foregroundStyle(BooksStyle.ink)
                Text("おつかれさまでした")
                    .foregroundStyle(BooksStyle.subInk)
                Button("もう一度") {
                    deck = stickies.filter { $0.reviewEnabled }.shuffled()
                    index = 0; showAnswer = false
                }
                .buttonStyle(CaptureButton()).frame(width: 160)
            }
        } else {
            ReviewCard(
                sticky: deck[index],
                showAnswer: $showAnswer,
                onNext: { showAnswer = false; index += 1 },
                onAgain: {
                    deck.append(deck[index])
                    showAnswer = false
                    index += 1
                }
            )
        }
    }
}

// MARK: - 1枚のカード

private struct ReviewCard: View {
    let sticky: Sticky
    @Binding var showAnswer: Bool
    var onNext: () -> Void
    var onAgain: () -> Void
    @Environment(VaultManager.self) private var vault

    @State private var aiQuestion: String?
    @State private var loadingQuestion = false

    private var displayMemo: String {
        let raw: String
        if let data = sticky.encryptedMemo { raw = vault.decrypt(data) ?? "" }
        else { raw = sticky.memo }
        // 末尾の ? / ？ は復習トリガー用なので表示しない
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("?") || trimmed.hasSuffix("？") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private var style: String { sticky.reviewStyle ?? "default" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(headerText)
                .font(.headline).foregroundStyle(BooksStyle.ink)

            questionBody

            if showAnswer {
                Divider().padding(.vertical, 2)
                answerBody
            }

            HStack(spacing: 10) {
                if showAnswer {
                    Button {
                        onAgain()
                    } label: { Text("もう一度").frame(maxWidth: .infinity) }
                        .buttonStyle(CaptureButton(ghost: true))
                    Button {
                        onNext()
                    } label: { Text("次へ").frame(maxWidth: .infinity) }
                        .buttonStyle(CaptureButton())
                } else {
                    Button { showAnswer = true } label: {
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
        .task(id: sticky.id) {
            if style == "default" { await loadQuestion() }
        }
    }

    private var headerText: String {
        switch style {
        case "qa":    return "p.\(sticky.pageNumber) · この内容覚えた？"
        case "vocab": return "p.\(sticky.pageNumber) · 単語"
        default:      return "p.\(sticky.pageNumber) · \(aiQuestion ?? "ここ、何の話だった？")"
        }
    }

    @ViewBuilder private var questionBody: some View {
        if style == "qa" {
            VStack(alignment: .leading, spacing: 8) {
                Text(sticky.marker)
                    .font(BooksStyle.serif(.body)).lineSpacing(6)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(sticky.color.color.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                if !sticky.clipBefore.isEmpty || !sticky.clipAfter.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        if let before = sticky.clipBefore.last {
                            Text(before).foregroundStyle(.secondary)
                        }
                        if let after = sticky.clipAfter.first {
                            Text(after).foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
            }
        } else if style == "vocab" {
            VStack(alignment: .leading, spacing: 6) {
                Text(sticky.heading)
                    .font(.title3.bold()).foregroundStyle(BooksStyle.ink)
                Text("この言葉の意味は？")
                    .font(.caption).foregroundStyle(BooksStyle.subInk)
            }
        } else {
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
    }

    @ViewBuilder private var answerBody: some View {
        if style == "vocab" {
            Text(sticky.marker)
                .font(BooksStyle.serif(.body)).lineSpacing(6)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(sticky.heading).font(.headline)
                if !displayMemo.isEmpty {
                    Text(displayMemo).foregroundStyle(.secondary)
                }
            }
        }
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
