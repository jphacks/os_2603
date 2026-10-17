import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var books: [Book]
    @State private var confirmDeleteAll = false

    private var stickyCount: Int { books.reduce(0) { $0 + $1.stickies.count } }
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(StickyColor.allCases, id: \.self) { CategoryNameField(color: $0) }
                } header: {
                    Text("カテゴリ（付箋の色の意味）")
                } footer: {
                    Text("色ごとに意味を決めておくと、付箋がたくさんあっても区別できます。")
                }

                Section("プライバシー") {
                    Label("ページ全体の画像は保存しません", systemImage: "eye.slash")
                    Label("文字の読み取り（OCR）は端末内で行います", systemImage: "iphone")
                    Label("ネットに送るのは、書誌情報を調べるときのISBNだけです", systemImage: "network")
                }
                .font(.subheadline)

                Section("データ") {
                    LabeledContent("本", value: "\(books.count) 冊")
                    LabeledContent("付箋", value: "\(stickyCount) 枚")
                    Button("すべての本と付箋を削除", role: .destructive) { confirmDeleteAll = true }
                }

                Section("このアプリについて") {
                    LabeledContent("バージョン", value: version)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("設定")
            .confirmationDialog("すべての本と付箋を削除しますか？",
                                isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("削除する", role: .destructive) {
                    for book in books { context.delete(book) }
                    try? context.save()
                }
            } message: {
                Text("この操作は元に戻せません。")
            }
        }
    }
}

private struct CategoryNameField: View {
    let color: StickyColor
    @AppStorage private var name: String

    init(color: StickyColor) {
        self.color = color
        _name = AppStorage(wrappedValue: color.defaultCategory, color.categoryKey)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(color.color).frame(width: 16, height: 16)
            TextField(color.defaultCategory, text: $name)
        }
    }
}
