import SwiftUI
import SwiftData

// 思い出すきっかけを示し、実物の教科書へ戻るための画面。
// 「読み直した」は mastered（覚えた）と独立して保存する。
struct ReviewView: View {
    @Environment(\.modelContext) private var context
    let stickies: [Sticky]
    var onClose: () -> Void

    @State private var deck: [Sticky] = []
    @State private var index = 0
    @State private var didStart = false
    @State private var showReadingList = false
    @State private var bookCheck: BookReviewTarget?
    @State private var saveError: String?

    private var available: [Sticky] {
        stickies.filter { $0.deletedAt == nil && $0.placed && !$0.mastered }
    }
    private var pending: [Sticky] {
        available.filter { $0.needsBookReview }
            .sorted { ($0.pageNumber, $0.order) < ($1.pageNumber, $1.order) }
    }

    var body: some View {
        ZStack {
            BooksStyle.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if deck.isEmpty {
                            emptyState
                        } else if index >= deck.count {
                            sessionEnd
                        } else {
                            card(deck[index])
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            guard !didStart else { return }
            didStart = true
            startSession()
        }
        .sheet(item: $bookCheck) { target in
            BookReviewSheet(sticky: target.sticky, onRead: {
                guard recordRead(target.sticky) else { return }
                bookCheck = nil
                if target.advanceAfterReading, index < deck.count,
                   deck[index].id == target.sticky.id { index += 1 }
            }, onLater: {
                bookCheck = nil
                if target.advanceAfterReading, index < deck.count,
                   deck[index].id == target.sticky.id { index += 1 }
            })
        }
        .sheet(isPresented: $showReadingList) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("本を開いて確認したい付箋")
                            .font(.title2.bold()).foregroundStyle(BooksStyle.ink)
                        if pending.isEmpty {
                            Text("あとで確認する付箋はありません")
                                .foregroundStyle(BooksStyle.subInk)
                        } else {
                            readingList
                        }
                    }.padding(20)
                }
                .background(BooksStyle.background)
                .navigationTitle("あとで教科書で確認")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("閉じる") { showReadingList = false }
                    }
                }
            }
        }
        .alert("記録を保存できませんでした", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button("閉じる", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "もう一度お試しください")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            BooksCloseButton { onClose() }
            Spacer()
            Button { showReadingList = true } label: {
                Label("あとで \(pending.count)", systemImage: "book.closed")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(BooksStyle.ink)
            .accessibilityLabel("あとで教科書で確認する付箋、\(pending.count)枚")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func card(_ sticky: Sticky) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("付箋を振り返る").font(.title2.bold())
                Spacer()
                Text("\(index + 1) / \(deck.count)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(BooksStyle.subInk)
            }
            Text(sticky.book?.title ?? "本の付箋")
                .font(.subheadline).foregroundStyle(BooksStyle.subInk)
            ProgressView(value: Double(index), total: Double(max(deck.count, 1)))
                .tint(BooksStyle.ink)
                .accessibilityLabel("振り返りの進捗")

            Text("ここに付箋を貼った理由、思い出せますか？")
                .font(.subheadline).foregroundStyle(BooksStyle.subInk)
            Text(sticky.heading).font(.title2.bold()).foregroundStyle(BooksStyle.ink)
            BookReviewClue(sticky: sticky)
            if let date = sticky.lastBookReviewAt {
                Text("前に教科書で確認した日：\(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(BooksStyle.subInk)
            }

            VStack(spacing: 12) {
                Button {
                    guard queue(sticky) else { return }
                    bookCheck = BookReviewTarget(sticky: sticky, advanceAfterReading: true)
                } label: {
                    Label("教科書で確認する", systemImage: "book")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(CaptureButton())
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { nextActions(sticky) }
                    VStack(spacing: 12) { nextActions(sticky) }
                }
            }
            Text("分からないところは、本の本文や図を読み直しましょう。")
                .font(.caption).foregroundStyle(BooksStyle.subInk)
        }
    }

    @ViewBuilder private func nextActions(_ sticky: Sticky) -> some View {
        Button {
            guard queue(sticky) else { return }
            index += 1
        } label: {
            Text("あとで確認").frame(maxWidth: .infinity)
        }.buttonStyle(CaptureButton(ghost: true))
        Button { index += 1 } label: {
            Text("次の付箋へ").frame(maxWidth: .infinity)
        }.buttonStyle(CaptureButton(ghost: true))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("振り返る付箋がありません", systemImage: "bookmark")
        } description: {
            Text("付箋の編集画面で「復習対象にする」をオンにすると、ここに表示されます。")
        }
    }

    private var sessionEnd: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("次に教科書を開くところ").font(.title2.bold())
            Text("\(deck.count)枚の付箋を振り返りました。")
                .foregroundStyle(BooksStyle.subInk)
            if pending.isEmpty {
                Text("あとで確認する付箋は残っていません。")
            } else {
                Text("読み直したい付箋が\(pending.count)枚あります。\n本が手元になくても、一覧は次回まで残ります。")
                    .foregroundStyle(BooksStyle.subInk)
                readingList
            }
            Button { startSession() } label: {
                Text("もう一度振り返る").frame(maxWidth: .infinity)
            }.buttonStyle(CaptureButton(ghost: true))
            Button("閉じる") { onClose() }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
        }
    }

    private var readingList: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(pending) { sticky in
                VStack(alignment: .leading, spacing: 10) {
                    Text(sticky.book?.title ?? "本の付箋")
                        .font(.caption).foregroundStyle(BooksStyle.subInk)
                    Text("\(BookReviewText.page(sticky.pageNumber)) · \(sticky.heading)")
                        .font(.headline).foregroundStyle(BooksStyle.ink)
                    // 同時に複数シートを開かず、一覧内でそのまま本に戻る案内をする。
                    Text("このページの本文・図を読み直してください。")
                        .font(.caption).foregroundStyle(BooksStyle.subInk)
                    Button("教科書で確認した") { _ = recordRead(sticky) }
                        .font(.subheadline.weight(.semibold))
                    Divider()
                }
            }
        }
    }

    private func startSession() {
        deck = available.filter { $0.reviewEnabled || $0.needsBookReview }
            .sorted {
                if $0.needsBookReview != $1.needsBookReview { return $0.needsBookReview }
                return ($0.pageNumber, $0.order) < ($1.pageNumber, $1.order)
            }
        index = 0
    }

    private func queue(_ sticky: Sticky) -> Bool {
        let wasPending = sticky.needsBookReview
        sticky.requestBookReview()
        do { try context.save(); return true }
        catch {
            sticky.needsBookReview = wasPending
            saveError = "確認したいページの記録を保存できませんでした。もう一度お試しください。"
            return false
        }
    }

    private func recordRead(_ sticky: Sticky) -> Bool {
        let wasPending = sticky.needsBookReview
        let previousDate = sticky.lastBookReviewAt
        sticky.recordBookReview()
        do { try context.save(); return true }
        catch {
            sticky.needsBookReview = wasPending
            sticky.lastBookReviewAt = previousDate
            saveError = "読み直した記録を保存できませんでした。もう一度お試しください。"
            return false
        }
    }
}

private struct BookReviewTarget: Identifiable {
    var id: UUID { sticky.id }
    let sticky: Sticky
    let advanceAfterReading: Bool
}

private struct BookReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sticky: Sticky
    var onRead: () -> Void
    var onLater: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("教科書を開く").font(.subheadline).foregroundStyle(BooksStyle.subInk)
                    Text(sticky.book?.title ?? "本の付箋")
                        .font(.title2.bold()).foregroundStyle(BooksStyle.ink)
                    Text(BookReviewText.page(sticky.pageNumber))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(BooksStyle.ink)
                    Text(sticky.heading).font(.title3.bold())
                    BookReviewClue(sticky: sticky)
                    Text("本文や図を読み直し、必要なら紙のノートに自分の言葉で書き直してみましょう。")
                        .foregroundStyle(BooksStyle.subInk)
                    Button(action: onRead) {
                        Text("教科書で確認した").frame(maxWidth: .infinity)
                    }.buttonStyle(CaptureButton())
                    Button("今は本がないので、あとで確認する", action: onLater)
                        .font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }.padding(24)
            }
            .background(BooksStyle.background)
            .navigationTitle("教科書で確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

private struct BookReviewClue: View {
    @Environment(VaultManager.self) private var vault
    let sticky: Sticky
    @State private var memo = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(BookReviewText.page(sticky.pageNumber)) の目印")
                    .font(.caption).foregroundStyle(BooksStyle.subInk)
                if let data = sticky.cropImageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("付箋を貼った部分の切り抜き")
                }
                if !sticky.marker.isEmpty && sticky.marker != "(図)" {
                    Text(sticky.marker).font(BooksStyle.serif(.body)).lineSpacing(5).lineLimit(4)
                    DisclosureGroup("原文と前後の文章を開く") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sticky.clipBefore.joined(separator: "\n")).foregroundStyle(BooksStyle.subInk)
                            Text(sticky.marker)
                            Text(sticky.clipAfter.joined(separator: "\n")).foregroundStyle(BooksStyle.subInk)
                        }.font(BooksStyle.serif(.subheadline)).padding(.top, 8)
                    }.font(.caption)
                }
            }
            if !memo.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("自分が残したメモ").font(.caption).foregroundStyle(BooksStyle.subInk)
                    Text(memo).font(.body).textSelection(.enabled)
                }
            }
        }
        .padding(18)
        .background(sticky.color.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
        .task(id: sticky.id) {
            let text: String
            if let data = sticky.encryptedMemo {
                text = vault.decrypt(data) ?? ""
            } else { text = sticky.memo }
            memo = BookReviewText.memo(text)
        }
    }
}

// 表示に使うメモから、以前の復習対象指定用の末尾 ? だけを取り除く。
enum BookReviewText {
    static func memo(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasSuffix("?") || result.hasSuffix("？") {
            result = String(result.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
    static func page(_ number: Int) -> String {
        number > 0 ? "p.\(number)" : "ページ番号を確認してください"
    }
}
