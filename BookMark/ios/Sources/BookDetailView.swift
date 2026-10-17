import SwiftUI
import SwiftData

// 本の画面（Apple Books の本の詳細のような見た目）：
// 上＝表紙の色の背景に大きな表紙・書名・著者、「パラパラ」「ページを撮る」
// 下＝白い面に「復習」、本の側面（付箋の位置）、「付箋／本の情報」

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
                VStack(spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: 22) {
                        if !notes.isEmpty {
                            reviewRow
                            VStack(alignment: .leading, spacing: 10) {
                                Text("付箋の位置").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                BookEdgeView(stickies: notes, lastPage: lastPage) { sticky in
                                    tab = .notes
                                    withAnimation { proxy.scrollTo(sticky.id, anchor: .top) }
                                }
                            }
                        }
                        Picker("表示", selection: $tab) {
                            Text("付箋 \(notes.count)").tag(DetailTab.notes)
                            Text("本の情報").tag(DetailTab.info)
                        }
                        .pickerStyle(.segmented)
                        switch tab {
                        case .notes: notesList
                        case .info: infoList
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.background,
                                in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
                }
            }
            // 上に引っぱったときは表紙の色、下は白
            .background(VStack(spacing: 0) { book.heroColor; Theme.background }.ignoresSafeArea())
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { takePhoto() } label: { Label("この本のページを撮る", systemImage: "camera") }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("この本を削除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
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

    // MARK: - 上（表紙の色の背景）

    private var hero: some View {
        VStack(spacing: 16) {
            BookCoverView(book: book)
                .frame(width: 168, height: 248)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                .padding(.top, 12)

            VStack(spacing: 6) {
                Text(book.title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                Text(statsLine)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 24)

            actionCard
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity)
        // 上（ナビゲーションバーの下）まで表紙の色で塗る
        .background(book.heroColor.padding(.top, -600))
        // 白い面の角丸を、表紙の色の上に少し重ねる
        .padding(.bottom, -24)
    }

    private var statsLine: String {
        var parts: [String] = []
        if let publisher = book.publisher, !publisher.isEmpty { parts.append(publisher) }
        if let pages = book.pageCount { parts.append("\(pages)ページ") }
        if let first = notes.first?.pageNumber, let last = notes.last?.pageNumber {
            parts.append(first == last ? "付箋 p.\(first)" : "付箋 p.\(first)〜p.\(last)")
        }
        return parts.isEmpty ? "まだ付箋がありません" : parts.joined(separator: " ・ ")
    }

    /// 「ブック 344ページ ［サンプル］［¥620］」の位置にあたるカード
    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("付箋 \(notes.count) 枚").font(.subheadline.weight(.semibold))
                Text(lastStickyText).font(.caption).opacity(0.65)
            }
            .foregroundStyle(.white)

            HStack(spacing: 10) {
                Button { showFlip = true } label: {
                    Label("パラパラ", systemImage: "book.pages")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                }
                .disabled(notes.isEmpty)
                .opacity(notes.isEmpty ? 0.5 : 1)

                Button { takePhoto() } label: {
                    Text("ページを撮る")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(Theme.ink)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private var lastStickyText: String {
        guard let latest = notes.map(\.createdAt).max() else { return "ページを撮って、貼りたい部分を囲みましょう" }
        return "最後に貼った日 \(Theme.dateFormatter.string(from: latest))"
    }

    // MARK: - 下（白い面）

    private var reviewRow: some View {
        Button { showReview = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("付箋から復習する").font(.subheadline.weight(.semibold))
                    Text("周りの文から、何の話だったか思い出す").font(.caption).foregroundStyle(Theme.subInk)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.subInk)
            }
            .foregroundStyle(Theme.ink)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var notesList: some View {
        if notes.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "note.text").font(.largeTitle).foregroundStyle(Theme.subInk)
                Text("まだ付箋がありません").font(.headline)
                Text("ページを撮って、貼りたい部分を囲んでみましょう")
                    .font(.footnote).foregroundStyle(Theme.subInk)
                Button("この本のページを撮る") { takePhoto() }
                    .buttonStyle(CaptureButton())
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(notes) { sticky in
                    Button { editing = sticky } label: { NoteCard(sticky: sticky) }
                        .buttonStyle(.plain)
                        .id(sticky.id)
                }
            }
        }
    }

    private var infoList: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let summary = book.summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("内容紹介").font(.headline)
                    Text(summary).font(.subheadline).foregroundStyle(Theme.subInk).lineSpacing(3)
                }
            }

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
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))

            if let isbn = book.isbn, BookInfoService.isValidISBN13(isbn) {
                Button {
                    Task { await refresh(isbn: isbn) }
                } label: {
                    Label(refreshing ? "取得中…" : "ISBNから本の情報を取り直す", systemImage: "arrow.clockwise")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ring)
                .disabled(refreshing)
                if let refreshMessage {
                    Text(refreshMessage).font(.caption).foregroundStyle(Theme.subInk)
                }
            }

            Button("この本を削除", role: .destructive) { confirmDelete = true }
                .font(.subheadline)
                .padding(.top, 4)
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
                Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, 16)
            }
        }
    }

    private func takePhoto() {
        lastBookId = book.id.uuidString
        appState.tab = .home
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
