import SwiftUI
import SwiftData

// ライブラリ：登録した本を表紙で並べる（Apple Books のライブラリのような 2 列）

struct ShelfView: View {
    @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]
    @State private var showAdd = false
    @State private var path: [Book] = []

    private let columns = [GridItem(.flexible(), spacing: 22, alignment: .bottom),
                           GridItem(.flexible(), spacing: 22, alignment: .bottom)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("すべての本").font(.headline).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(books.count) 冊").font(.subheadline).foregroundStyle(Theme.subInk)
                    }
                    Divider()
                    LazyVGrid(columns: columns, spacing: 30) {
                        ForEach(books) { book in
                            NavigationLink(value: book) { BookCell(book: book) }
                                .buttonStyle(.plain)
                        }
                        Button { showAdd = true } label: { addCell }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("ライブラリ")
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

    private var addCell: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.card)
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "barcode.viewfinder").font(.title)
                        Text("本を登録").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Theme.subInk)
                }
            Text(" ").font(.footnote)
            Text(" ").font(.caption)
        }
    }
}

private struct BookCell: View {
    let book: Book

    private var count: Int { book.stickies.filter(\.placed).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookCoverView(book: book)
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) { stickyTabs }
            Text(book.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            HStack {
                Text(count == 0 ? "付箋なし" : "付箋 \(count) 枚")
                Spacer()
                Image(systemName: "ellipsis")
            }
            .font(.caption)
            .foregroundStyle(Theme.subInk)
        }
    }

    /// 表紙の上端から少しのぞく付箋（色ごとに1枚）
    private var stickyTabs: some View {
        let colors = StickyColor.allCases.filter { c in book.stickies.contains { $0.placed && $0.color == c } }
        return HStack(spacing: 3) {
            ForEach(colors, id: \.self) { c in
                UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                    .fill(c.color)
                    .frame(width: 9, height: 14)
            }
        }
        .offset(x: -8, y: -10)
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
