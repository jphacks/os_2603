import SwiftUI
import SwiftData

struct ShelfView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]
    @State private var showAdd = false
    @State private var path: [Book] = []
    @State private var didAutoOpen = false

    private let columns = [GridItem(.flexible(), spacing: 22, alignment: .top),
                           GridItem(.flexible(), spacing: 22, alignment: .top)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 28) {
                    ForEach(books) { book in
                        NavigationLink(value: book) {
                            BookCard(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        showAdd = true
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(BooksStyle.card)
                                .aspectRatio(2 / 3, contentMode: .fit)
                                .overlay {
                                    VStack(spacing: 6) {
                                        Image(systemName: "plus").font(.title2)
                                        Text("本を追加").font(.subheadline.weight(.semibold))
                                    }
                                    .foregroundStyle(BooksStyle.subInk)
                                }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }
            .background(BooksStyle.background)
            .navigationTitle("BookMark")
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
            BookCoverView(book: book)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            Text(book.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BooksStyle.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(book.author ?? "著者不明")
                .font(.caption).foregroundStyle(BooksStyle.subInk)
                .lineLimit(1)
            let active = book.stickies.filter { !$0.mastered }.count
            let mastered = book.stickies.filter { $0.mastered }.count
            HStack(spacing: 4) {
                Text("付箋 \(active)").font(.caption).bold()
                    .foregroundStyle(BooksStyle.ink)
                if mastered > 0 {
                    Text("✓\(mastered)").font(.caption2).foregroundStyle(BooksStyle.subInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
