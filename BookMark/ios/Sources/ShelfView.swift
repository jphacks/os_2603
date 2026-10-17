import SwiftUI
import SwiftData

struct ShelfView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]
    @State private var showAdd = false
    @State private var path: [Book] = []
    @State private var didAutoOpen = false

    private let columns = [GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(books) { book in
                        NavigationLink(value: book) {
                            BookCard(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        showAdd = true
                    } label: {
                        VStack {
                            Image(systemName: "plus")
                            Text("本を追加").font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 132)
                        .foregroundStyle(.secondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                .foregroundStyle(.secondary.opacity(0.5)))
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0.969, green: 0.957, blue: 0.925))
            .navigationTitle("📖 BookMark")
            .navigationDestination(for: Book.self) { book in
                BookDetailView(book: book)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Label("本を追加", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddBookSheet()
            }
            .onAppear {
                seedIfEmpty()
                autoOpenLastBook()
            }
        }
    }

    private func seedIfEmpty() {
        guard books.isEmpty else { return }
        context.insert(Book(title: "オペレーティングシステム 第3版", author: "田中 ほか"))
        context.insert(Book(title: "アルゴリズムとデータ構造 入門", author: "佐藤"))
    }

    // 起動時、最後に開いた本の撮影画面から始める（本を選ぶ手間をなくす）。
    private func autoOpenLastBook() {
        guard !didAutoOpen else { return }
        didAutoOpen = true
        if let id = AppStore.lastBookId,
           let book = books.first(where: { $0.id.uuidString == id }) {
            path = [book]
        }
    }
}

private struct BookCard: View {
    let book: Book
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(book.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            Text(book.author ?? "著者不明")
                .font(.caption).foregroundStyle(.secondary)
            Text("付箋 \(book.stickies.count)")
                .font(.caption).bold()
                .foregroundStyle(Color(red: 0.75, green: 0.26, blue: 0.17))
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(14)
        .background(Color(red: 1.0, green: 0.992, blue: 0.973))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: 0.75, green: 0.26, blue: 0.17))
                .frame(width: 5)
                .padding(.vertical, 12)
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.08)))
    }
}

private struct AddBookSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var author = ""
    @State private var isbn = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("本の情報") {
                    TextField("タイトル", text: $title)
                    TextField("著者（任意）", text: $author)
                    TextField("ISBN（任意・バーコードは本番で）", text: $isbn)
                        .keyboardType(.numbersAndPunctuation)
                }
            }
            .navigationTitle("本を追加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        let b = Book(
                            title: title.isEmpty ? "無題の本" : title,
                            author: author.isEmpty ? nil : author,
                            isbn: isbn.isEmpty ? nil : isbn)
                        context.insert(b)
                        dismiss()
                    }.disabled(title.isEmpty)
                }
            }
        }
    }
}
