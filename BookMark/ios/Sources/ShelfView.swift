import SwiftUI
import SwiftData

// 本：登録した本の一覧（表紙つき）

struct ShelfView: View {
    @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]
    @State private var showAdd = false
    @State private var path: [Book] = []

    private let columns = [GridItem(.flexible(), spacing: 18),
                           GridItem(.flexible(), spacing: 18),
                           GridItem(.flexible(), spacing: 18)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(books) { book in
                        NavigationLink(value: book) { BookCell(book: book) }
                            .buttonStyle(.plain)
                    }
                    Button { showAdd = true } label: {
                        Color.clear
                            .aspectRatio(2 / 3, contentMode: .fit)
                            .overlay {
                                VStack(spacing: 6) {
                                    Image(systemName: "plus").font(.title2)
                                    Text("本を登録").font(.caption)
                                }
                                .foregroundStyle(Theme.subInk)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                    .foregroundStyle(Theme.subInk.opacity(0.5)))
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("本")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Label("本を登録", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
            .sheet(isPresented: $showAdd) {
                AddBookSheet { path.append($0) }
            }
        }
    }
}

private struct BookCell: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookCoverView(book: book)
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) { stickyTabs }
            Text(book.title)
                .font(Theme.serif(.footnote))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text("付箋 \(book.stickies.filter(\.placed).count)")
                .font(.caption2).foregroundStyle(Theme.subInk)
        }
    }

    /// 表紙の上端から少しのぞく付箋（色ごとに1枚）
    private var stickyTabs: some View {
        let colors = StickyColor.allCases.filter { c in book.stickies.contains { $0.placed && $0.color == c } }
        return HStack(spacing: 3) {
            ForEach(colors, id: \.self) { c in
                UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                    .fill(c.color)
                    .frame(width: 8, height: 12)
            }
        }
        .offset(x: -6, y: -8)
    }
}

// MARK: - 本の登録（ISBNバーコード → 書誌情報を自動取得）

struct AddBookSheet: View {
    var onAdded: (Book) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var books: [Book]

    @State private var isbn = ""
    @State private var title = ""
    @State private var author = ""
    @State private var info: BookInfo?
    @State private var cover: Data?
    @State private var lookingUp = false
    @State private var message: String?
    @State private var scanned = false

    private var existing: Book? {
        isbn.isEmpty ? nil : books.first { $0.isbn == isbn }
    }

    var body: some View {
        NavigationStack {
            Form {
                if ISBNScannerView.isSupported && !scanned {
                    Section {
                        ISBNScannerView { handleScanned($0) }
                            .frame(height: 200)
                            .listRowInsets(EdgeInsets())
                    } header: {
                        Text("裏表紙のバーコードをかざす")
                    } footer: {
                        Text("978 または 979 で始まるバーコードを読み取ります。")
                    }
                }

                Section("ISBN") {
                    HStack {
                        TextField("ISBN（13桁）", text: $isbn)
                            .keyboardType(.numberPad)
                            .onChange(of: isbn) { _, v in
                                let digits = v.filter(\.isNumber)
                                if digits != v { isbn = digits }
                            }
                        Button("検索") { Task { await lookup() } }
                            .disabled(!BookInfoService.isValidISBN13(isbn) || lookingUp)
                    }
                    if lookingUp { ProgressView("本の情報を調べています…") }
                    if let message { Text(message).font(.caption).foregroundStyle(Theme.subInk) }
                }

                Section("本の情報") {
                    HStack(alignment: .top, spacing: 14) {
                        if let cover, let image = UIImage(data: cover) {
                            Image(uiImage: image).resizable().scaledToFit()
                                .frame(width: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        VStack {
                            TextField("タイトル", text: $title)
                            Divider()
                            TextField("著者（任意）", text: $author)
                        }
                    }
                }

                if let existing {
                    Section {
                        Button("登録済みの「\(existing.title)」を開く") {
                            dismiss()
                            onAdded(existing)
                        }
                    }
                }
            }
            .navigationTitle("本を登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("登録") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func handleScanned(_ code: String) {
        guard !scanned else { return }
        scanned = true
        isbn = code
        if let existing {
            dismiss()
            onAdded(existing)
            return
        }
        Task { await lookup() }
    }

    private func lookup() async {
        lookingUp = true
        defer { lookingUp = false }
        guard let found = await BookInfoService.lookup(isbn: isbn) else {
            message = "本の情報が見つかりませんでした。タイトルを入力してください。"
            return
        }
        info = found
        title = found.title
        author = found.author ?? ""
        message = nil
        cover = await BookInfoService.fetchCover(found.coverURL)
    }

    private func save() {
        if let existing {
            dismiss()
            onAdded(existing)
            return
        }
        let book = Book(
            title: title.trimmingCharacters(in: .whitespaces),
            author: author.isEmpty ? nil : author,
            isbn: isbn.isEmpty ? nil : isbn)
        if var info {
            info.title = book.title
            info.author = book.author
            book.apply(info, cover: cover)
        }
        context.insert(book)
        try? context.save()
        dismiss()
        onAdded(book)
    }
}
