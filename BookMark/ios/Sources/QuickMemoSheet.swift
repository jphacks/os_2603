import SwiftUI
import SwiftData

// メモだけモード（A5）：撮影せず「ページ番号＋メモ」で付箋を作る（placed=false）。
// メモは Speech で音声入力もできる。後でそのページを撮って囲むと配置される。
struct QuickMemoSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(VaultManager.self) private var vault
    @Environment(\.dismiss) private var dismiss
    let book: Book

    @State private var pageText: String
    @State private var memo = ""
    @State private var speech = SpeechRecognizer()

    init(book: Book, defaultPage: Int?) {
        self.book = book
        _pageText = State(initialValue: defaultPage.map(String.init) ?? "")
    }

    private var page: Int? {
        let n = Int(pageText.filter { $0.isNumber })
        return (n ?? 0) > 0 ? n : nil
    }
    private var canSave: Bool {
        page != nil && !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("ページ") {
                    TextField("例)12", text: $pageText).keyboardType(.numberPad)
                }
                Section("メモ") {
                    TextField("覚えたいこと・気づいたこと", text: $memo, axis: .vertical)
                        .lineLimit(3...8)
                    if speech.isSupported {
                        Button {
                            speech.toggle(base: memo) { memo = $0 }
                        } label: {
                            Label(speech.isRecording ? "停止" : "声で入力",
                                  systemImage: speech.isRecording ? "stop.circle.fill" : "mic.fill")
                                .foregroundStyle(speech.isRecording ? .red : BooksStyle.accent)
                        }
                    }
                    if let e = speech.errorMessage {
                        Text(e).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("後でそのページを撮って範囲を囲むと、このメモが配置されます")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("メモだけ残す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { speech.stop(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(!canSave)
                }
            }
            .onDisappear { speech.stop() }
        }
    }

    private func save() {
        guard let pn = page else { return }
        speech.stop()
        let text = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let sticky = Sticky(pageNumber: pn, placed: false, marker: "",
                            clipBefore: [], clipAfter: [],
                            color: StickyColor.cycle(book.stickies.count), book: book)
        if let enc = vault.encrypt(text) { sticky.encryptedMemo = enc } else { sticky.memo = text }
        sticky.heading = Sticky.makeHeading(memo: text, marker: "")
        context.insert(sticky)
        AppStore.setLastPage(pn, for: book.id)
        dismiss()
    }
}
