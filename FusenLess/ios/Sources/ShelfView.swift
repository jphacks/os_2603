import SwiftUI
import SwiftData
import AVFoundation

struct ShelfView: View {
    @Environment(\.modelContext) private var context
    @Environment(VaultManager.self) private var vault
    @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]
    @State private var showAdd = false
    @State private var path: [Book] = []
@State private var query = ""
    @State private var editMode = false
    @State private var deleteTarget: Book?
    @State private var showQuickCamera = false
    @State private var quickPhoto: UIImage?
    @State private var showBookPicker = false
    @State private var showCameraAlert = false

    private let columns = [GridItem(.flexible(), spacing: 22, alignment: .top),
                           GridItem(.flexible(), spacing: 22, alignment: .top)]

    // 全ての本の付箋を、見出し・目印・メモ・色名から検索（A16）。
    private var matches: [Sticky] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var out: [Sticky] = []
        for book in books {
            for s in book.stickies where !s.mastered && s.deletedAt == nil {
                let memo = s.encryptedMemo.flatMap { vault.decrypt($0) } ?? s.memo
                let hay = [s.heading, s.marker, memo, book.title, AppStore.colorName(s.color)]
                    .joined(separator: " ").lowercased()
                if hay.contains(q) { out.append(s) }
            }
        }
        return out.sorted { ($0.book?.title ?? "", $0.pageNumber) < ($1.book?.title ?? "", $1.pageNumber) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
            if query.isEmpty {
            ScrollView {
                // 撮影ボタン（先に撮って後から教科書を選ぶ）
                Button {
                    let status = AVCaptureDevice.authorizationStatus(for: .video)
                    if status == .denied || status == .restricted {
                        showCameraAlert = true
                    } else {
                        showQuickCamera = true
                    }
                } label: {
                    Label("カメラで撮る", systemImage: "camera.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(BooksStyle.ink, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 28) {
                    ForEach(books) { book in
                        if editMode {
                            BookCard(book: book)
                                .overlay(alignment: .topTrailing) {
                                    Button { deleteTarget = book } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(.white, .red)
                                    }
                                    .offset(x: 6, y: -6)
                                }
                        } else {
                            NavigationLink(value: book) {
                                BookCard(book: book)
                            }
                            .buttonStyle(.plain)
                        }
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
            } else {
                SearchResultsList(matches: matches) { book in path = [book] }
            }
            }
            .background(BooksStyle.background)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "付箋を検索（見出し・目印・メモ）")
            .navigationTitle("FusenLess")
            .navigationDestination(for: Book.self) { book in
                BookDetailView(book: book)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation { editMode.toggle() }
                    } label: {
                        Label(editMode ? "完了" : "削除", systemImage: editMode ? "checkmark" : "trash")
                    }
                    .disabled(books.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Label("本を追加", systemImage: "plus")
                    }
                }
            }
            .alert("この本を削除しますか？", isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )) {
                Button("削除", role: .destructive) {
                    if let book = deleteTarget {
                        context.delete(book)
                        deleteTarget = nil
                        if books.count <= 1 { editMode = false }
                    }
                }
                Button("キャンセル", role: .cancel) { deleteTarget = nil }
            } message: {
                Text(deleteTarget.map { "「\($0.title)」と全ての付箋が削除されます" } ?? "")
            }
            .sheet(isPresented: $showAdd) {
                AddBookSheet()
            }
            .fullScreenCover(isPresented: $showQuickCamera) {
                CameraPicker { img in
                    showQuickCamera = false
                    if let img {
                        quickPhoto = img
                        showBookPicker = true
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showBookPicker) {
                BookPickerSheet(books: books) { book in
                    showBookPicker = false
                    path = [book]
                    // BookDetailViewに写真を渡すためNotificationCenterを使用
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(
                            name: .quickPhotoTaken,
                            object: quickPhoto)
                        quickPhoto = nil
                    }
                }
            }
            .alert("カメラへのアクセスが許可されていません", isPresented: $showCameraAlert) {
                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("設定 → FusenLess → カメラ をオンにしてください")
            }
            .onAppear { seedIfEmpty() }
        }
    }

    private func seedIfEmpty() {
        guard books.isEmpty else { return }
        context.insert(Book(title: "オペレーティングシステム 第3版", author: "田中 ほか"))
        context.insert(Book(title: "アルゴリズムとデータ構造 入門", author: "佐藤"))
    }

}

private struct SearchResultsList: View {
    let matches: [Sticky]
    var onOpen: (Book) -> Void
    @Environment(VaultManager.self) private var vault

    var body: some View {
        if matches.isEmpty {
            ContentUnavailableView.search
        } else {
            List {
                ForEach(matches) { s in
                    Button { if let b = s.book { onOpen(b) } } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2).fill(s.color.color).frame(width: 4, height: 16)
                                Text(s.heading).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BooksStyle.ink).lineLimit(1)
                                Spacer()
                                Text(AppStore.colorName(s.color))
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(s.color.color.opacity(0.4), in: Capsule())
                                    .foregroundStyle(BooksStyle.ink)
                            }
                            Text(s.marker).font(.caption).foregroundStyle(BooksStyle.subInk).lineLimit(1)
                            HStack(spacing: 8) {
                                Text(s.book?.title ?? "本").font(.caption2).foregroundStyle(BooksStyle.subInk)
                                Text("p.\(s.pageNumber)").font(.caption2).foregroundStyle(BooksStyle.subInk)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
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
            let alive = book.stickies.filter { $0.deletedAt == nil }
            let active = alive.filter { !$0.mastered }.count
            let mastered = alive.filter { $0.mastered }.count
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
    @State private var showScanner = false
    @State private var lookupMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("本の情報") {
                    TextField("タイトル", text: $title)
                    TextField("著者（任意）", text: $author)
                    TextField("ISBN（任意）", text: $isbn)
                        .keyboardType(.numbersAndPunctuation)
                    Button {
                        showScanner = true
                    } label: {
                        Label("バーコードで読み取る", systemImage: "barcode.viewfinder")
                    }
                    if let lookupMessage {
                        Text(lookupMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("本を追加")
            .sheet(isPresented: $showScanner) {
                BarcodeScanSheet { code in onScanned(code) }
            }
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

    private func onScanned(_ code: String) {
        let digits = code.filter { $0.isNumber }
        isbn = digits
        lookupMessage = "ISBN \(digits) を読み取りました。書名を照会中…"
        Task {
            let info = await BookLookup.fetch(isbn: digits)
            await MainActor.run {
                if let t = info?.title, title.isEmpty { title = t }
                if let a = info?.author, author.isEmpty { author = a }
                lookupMessage = info?.title != nil ? "書名を自動入力しました" : "書名は見つかりませんでした（手入力できます）"
            }
        }
    }
}

// MARK: - 教科書選択シート（カメラ先撮りフロー用）

extension Notification.Name {
    static let quickPhotoTaken = Notification.Name("quickPhotoTaken")
}

private struct BookPickerSheet: View {
    let books: [Book]
    var onPick: (Book) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(books) { book in
                    Button {
                        onPick(book)
                    } label: {
                        HStack(spacing: 12) {
                            BookCoverView(book: book, titleFont: .system(size: 10, weight: .bold))
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(book.title).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BooksStyle.ink)
                                if let author = book.author {
                                    Text(author).font(.caption).foregroundStyle(BooksStyle.subInk)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("教科書を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }
}
