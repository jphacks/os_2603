import SwiftUI
import SwiftData

// 本の画面：表紙・書名・著者・紹介 ／「付箋」「本の情報」タブ ／ 右端に本の側面と付箋タブ。

struct BookDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    // AppStore.lastBookId と同じキー（ホームはこの本から始まる）
    @AppStorage("bookmark.lastBookId") private var lastBookId = ""
    @Bindable var book: Book

    @State private var tab: DetailTab = .notes
    @State private var editing: Sticky?
    @State private var confirmDelete = false
    @State private var refreshing = false
    @State private var refreshMessage: String?
    @State private var showFlip = false
    @State private var showReview = false

    enum DetailTab { case notes, info }

    private var notes: [Sticky] { book.placedStickies }
    private var lastPage: Int {
        max(book.pageCount ?? 0, notes.map(\.pageNumber).max() ?? 0, 1)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    recallButtons
                    tabBar
                    switch tab {
                    case .notes: notesList
                    case .info: infoList
                    }
                }
                .padding(.leading, 20)
                .padding(.trailing, tab == .notes ? 40 : 20)
                .padding(.vertical, 12)
            }
            .overlay(alignment: .trailing) {
                if tab == .notes && !notes.isEmpty {
                    BookEdgeView(stickies: notes, lastPage: lastPage) { sticky in
                        withAnimation { proxy.scrollTo(sticky.id, anchor: .top) }
                    }
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    lastBookId = book.id.uuidString
                    appState.tab = .home
                } label: {
                    Label("この本のページを撮る", systemImage: "camera")
                }
            }
        }
        .sheet(item: $editing) { StickyEditor(sticky: $0) }
        .fullScreenCover(isPresented: $showFlip) {
            FlipView(stickies: notes, bookTitle: book.title) { showFlip = false }
        }
        .fullScreenCover(isPresented: $showReview) {
            ReviewView(stickies: notes) { showReview = false }
        }
        .onAppear { lastBookId = book.id.uuidString }
        .confirmationDialog("「\(book.title)」と付箋をすべて削除しますか？",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                context.delete(book)
                dismiss()
            }
        }
    }

    // MARK: - ヘッダー

    /// 本がなくても思い出す（パラパラ）・試験前に復習する
    private var recallButtons: some View {
        HStack(spacing: 10) {
            Button { showFlip = true } label: {
                Label("パラパラ", systemImage: "book").frame(maxWidth: .infinity)
            }
            Button { showReview = true } label: {
                Label("復習", systemImage: "brain.head.profile").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(CaptureButton(ghost: true))
        .disabled(notes.isEmpty)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            BookCoverView(book: book).frame(width: 96, height: 140)
            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(Theme.serif(.title2))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let author = book.author, !author.isEmpty {
                    Text(author).font(.subheadline).foregroundStyle(Theme.subInk)
                }
                if let summary = book.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(Theme.subInk)
                        .lineSpacing(3)
                        .lineLimit(4)
                        .padding(.top, 6)
                }
            }
        }
        .padding(.top, 8)
    }

    private var tabBar: some View {
        HStack(spacing: 32) {
            tabButton("付箋 \(notes.count)", .notes)
            tabButton("本の情報", .info)
            Spacer()
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1)
        }
    }

    private func tabButton(_ title: String, _ value: DetailTab) -> some View {
        Button { tab = value } label: {
            VStack(spacing: 10) {
                Text(title)
                    .font(.body.weight(tab == value ? .semibold : .regular))
                    .foregroundStyle(tab == value ? Theme.ink : Theme.subInk)
                Rectangle()
                    .fill(tab == value ? Theme.accent : .clear)
                    .frame(height: 2.5)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    // MARK: - 付箋

    @ViewBuilder
    private var notesList: some View {
        if notes.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "tag").font(.largeTitle).foregroundStyle(Theme.subInk)
                Text("まだ付箋がありません").font(Theme.serif(.headline))
                Text("ホームでページを撮って、行をタップしてみましょう")
                    .font(.footnote).foregroundStyle(Theme.subInk)
                Button("この本のページを撮る") {
                    lastBookId = book.id.uuidString
                    appState.tab = .home
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            LazyVStack(spacing: 16) {
                ForEach(notes) { sticky in
                    Button { editing = sticky } label: { NoteCard(sticky: sticky) }
                        .buttonStyle(.plain)
                        .id(sticky.id)
                }
            }
        }
    }

    // MARK: - 本の情報

    private var infoList: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 0) {
                infoRow("タイトル", book.title)
                infoRow("著者", book.author)
                infoRow("出版社", book.publisher)
                infoRow("出版日", book.publishedDate)
                infoRow("ページ数", book.pageCount.map { "\($0) ページ" })
                infoRow("ISBN", book.isbn)
                infoRow("登録日", Theme.dateFormatter.string(from: book.createdAt))
                infoRow("付箋", "\(notes.count) 枚", last: true)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))

            if let isbn = book.isbn, BookInfoService.isValidISBN13(isbn) {
                Button {
                    Task { await refresh(isbn: isbn) }
                } label: {
                    Label(refreshing ? "取得中…" : "ISBNから本の情報を取り直す", systemImage: "arrow.clockwise")
                }
                .disabled(refreshing)
                if let refreshMessage {
                    Text(refreshMessage).font(.caption).foregroundStyle(Theme.subInk)
                }
            }

            Button("この本を削除", role: .destructive) { confirmDelete = true }
                .padding(.top, 8)
        }
    }

    private func infoRow(_ label: String, _ value: String?, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(label).foregroundStyle(Theme.subInk)
                Spacer(minLength: 16)
                Text(value?.isEmpty == false ? value! : "—")
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.trailing)
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            if !last {
                Rectangle().fill(Color.black.opacity(0.05)).frame(height: 1).padding(.leading, 16)
            }
        }
    }

    private func refresh(isbn: String) async {
        refreshing = true
        defer { refreshing = false }
        guard let info = await BookInfoService.lookup(isbn: isbn) else {
            refreshMessage = "本の情報が見つかりませんでした"
            return
        }
        let cover = await BookInfoService.fetchCover(info.coverURL)
        book.apply(info, cover: cover)
        refreshMessage = "本の情報を更新しました"
    }
}
