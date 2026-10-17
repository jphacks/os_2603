import SwiftUI
import SwiftData
import PhotosUI

// ホーム：読んでいる本を選んで、ページを撮る → 行をタップで付箋。

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]
    @AppStorage("homeBookID") private var homeBookID = ""

    @State private var photo: UIImage?
    @State private var ocr: OCRResult?
    @State private var pageNumber: Int?
    @State private var recognizing = false
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var editing: Sticky?
    @State private var showAddBook = false

    private var book: Book? {
        books.first { $0.id.uuidString == homeBookID } ?? books.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if recognizing {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("文字を認識中…").font(.subheadline).foregroundStyle(Theme.subInk)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let photo, let ocr, let book {
                    PhotoReaderView(
                        image: photo, ocr: ocr, pageNumber: $pageNumber,
                        book: book,
                        onEdit: { editing = $0 },
                        onClose: { clearPhoto() })
                } else {
                    start
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("ホーム")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { StickyEditor(sticky: $0) }
            .sheet(isPresented: $showAddBook) {
                AddBookSheet { homeBookID = $0.id.uuidString }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in
                    showCamera = false          // 撮影/キャンセル後にカメラを閉じる
                    if let img { runOCR(img) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, newItem in loadPicked(newItem) }
        }
    }

    private var start: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let book {
                    bookSelector(book)
                    captureButtons
                    Text("📸 コツ: 片方のページだけを正面から・明るく・なるべく平らに")
                        .font(.caption).foregroundStyle(Theme.subInk)
                        .frame(maxWidth: .infinity)
                    recentNotes(book)
                } else {
                    ContentUnavailableView {
                        Label("本がまだありません", systemImage: "books.vertical")
                    } description: {
                        Text("裏表紙のISBNバーコードをかざして、読んでいる本を登録しましょう")
                    } actions: {
                        Button("本を登録する") { showAddBook = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 60)
                }
            }
            .padding(20)
        }
    }

    private func bookSelector(_ book: Book) -> some View {
        Menu {
            ForEach(books) { b in
                Button {
                    homeBookID = b.id.uuidString
                } label: {
                    if b.id == book.id {
                        Label(b.title, systemImage: "checkmark")
                    } else {
                        Text(b.title)
                    }
                }
            }
            Divider()
            Button { showAddBook = true } label: { Label("本を登録", systemImage: "plus") }
        } label: {
            HStack(spacing: 14) {
                BookCoverView(book: book).frame(width: 46, height: 66)
                VStack(alignment: .leading, spacing: 3) {
                    Text("読んでいる本").font(.caption).foregroundStyle(Theme.subInk)
                    Text(book.title)
                        .font(Theme.serif(.headline))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").foregroundStyle(Theme.subInk)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        }
    }

    private var captureButtons: some View {
        VStack(spacing: 10) {
            Button { showCamera = true } label: {
                VStack(spacing: 10) {
                    Image(systemName: "camera.fill").font(.system(size: 34))
                    Text("ページを撮る").font(.headline)
                    Text("撮って、付箋を貼りたい行をタップ").font(.caption).opacity(0.85)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            .buttonStyle(CaptureButton())
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

            HStack(spacing: 10) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("写真を選ぶ", systemImage: "photo").frame(maxWidth: .infinity)
                }
                .buttonStyle(CaptureButton(ghost: true))
                Button { runSample() } label: {
                    Label("サンプルで試す", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                }
                .buttonStyle(CaptureButton(ghost: true))
            }
        }
    }

    @ViewBuilder
    private func recentNotes(_ book: Book) -> some View {
        let recent = book.stickies.filter(\.placed).sorted { $0.createdAt > $1.createdAt }.prefix(3)
        if !recent.isEmpty {
            Text("最近の付箋").font(Theme.serif(.headline)).foregroundStyle(Theme.ink).padding(.top, 6)
            ForEach(Array(recent)) { s in
                Button { editing = s } label: { NoteCard(sticky: s) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func runOCR(_ image: UIImage) {
        recognizing = true
        Task {
            let result = await OCR.recognize(image)
            await MainActor.run {
                self.photo = image
                self.ocr = result
                self.pageNumber = result.pageNumber
                self.recognizing = false
            }
        }
    }

    private func runSample() {
        let page = Sample.pages[0]
        runOCR(Sample.render(page))
    }

    private func loadPicked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                await MainActor.run { runOCR(img) }
            }
            await MainActor.run { pickerItem = nil }
        }
    }

    private func clearPhoto() {
        photo = nil
        ocr = nil
        pageNumber = nil
    }
}

// MARK: - 写真ビュー（画像の上に行オーバーレイ・付箋配置）

struct PhotoReaderView: View {
    @Environment(\.modelContext) private var context
    let image: UIImage
    let ocr: OCRResult
    @Binding var pageNumber: Int?
    @Bindable var book: Book
    var onEdit: (Sticky) -> Void
    var onClose: () -> Void

    @AppStorage("lastStickyColor") private var lastColor = StickyColor.yellow.rawValue
    @State private var pageText: String = ""

    private var lineTexts: [String] { ocr.lines.map { $0.text } }

    // 目印のあいまい一致で、このページの付箋を行へ自動配置。
    private var anchors: [Int: Sticky] {
        guard let pn = pageNumber else { return [:] }
        var map: [Int: Sticky] = [:]
        for s in book.stickies where s.placed && s.pageNumber == pn {
            if let i = findBestLine(marker: s.marker, lines: lineTexts) {
                map[i] = s
            }
        }
        return map
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text("ページ")
                        TextField("例)12", text: $pageText)
                            .frame(width: 56)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .onChange(of: pageText) { _, v in
                                pageNumber = Int(v.filter { $0.isNumber })
                            }
                    }
                    .font(.footnote).bold()
                    Spacer()
                    Button("閉じる") { onClose() }.buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                GeometryReader { geo in
                    let w = geo.size.width
                    let h = w * image.size.height / max(image.size.width, 1)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: w, height: h)
                        ForEach(Array(ocr.lines.enumerated()), id: \.element.id) { idx, line in
                            let r = line.rect
                            let sticky = anchors[idx]
                            Rectangle()
                                .fill((sticky?.color.color ?? .clear).opacity(sticky == nil ? 0.001 : 0.4))
                                .overlay(alignment: .trailing) {
                                    if let s = sticky {
                                        UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3)
                                            .fill(s.color.color)
                                            .frame(width: 10)
                                            .offset(x: 10)
                                    }
                                }
                                .frame(width: r.width * w, height: max(r.height * h, 18))
                                .contentShape(Rectangle())
                                .position(x: (r.minX + r.width / 2) * w,
                                          y: (r.minY + r.height / 2) * h)
                                .onTapGesture { tap(idx) }
                        }
                    }
                    .frame(width: w, height: h)
                }
                .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
                .padding(.horizontal, 16)

                Text(pageNumber == nil
                     ? "ページ番号を入れると付箋をつけられます"
                     : "写真の行をタップで付箋。次に同じページを撮ると自動で戻ります")
                    .font(.caption).foregroundStyle(Theme.subInk)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 20)
            }
        }
        .onAppear {
            if let pn = pageNumber { pageText = String(pn) }
        }
    }

    private func tap(_ i: Int) {
        if let s = anchors[i] { onEdit(s); return }
        guard let pn = pageNumber else { return }
        let texts = lineTexts
        if normalizeText(texts[i]).isEmpty { return }
        let before = Array(texts[max(0, i - 2)..<i])
        let after = Array(texts[(i + 1)..<min(texts.count, i + 3)])
        let sticky = Sticky(
            pageNumber: pn, placed: true, marker: texts[i],
            clipBefore: before, clipAfter: after,
            color: StickyColor(rawValue: lastColor) ?? .yellow, book: book)
        context.insert(sticky)
    }
}

// MARK: - 付箋編集

struct StickyEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("lastStickyColor") private var lastColor = StickyColor.yellow.rawValue
    @Bindable var sticky: Sticky

    var body: some View {
        NavigationStack {
            Form {
                Section("目印") {
                    Text(sticky.marker).font(Theme.serif(.subheadline))
                    if !sticky.clipBefore.isEmpty || !sticky.clipAfter.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(sticky.clipBefore, id: \.self) {
                                Text($0).foregroundStyle(.secondary)
                            }
                            Text(sticky.marker).bold()
                            ForEach(sticky.clipAfter, id: \.self) {
                                Text($0).foregroundStyle(.secondary)
                            }
                        }.font(.caption)
                    }
                }
                Section("メモ") {
                    TextField("気づいたこと・覚えたいこと", text: $sticky.memo, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: sticky.memo) { _, v in
                            sticky.heading = Sticky.makeHeading(memo: v, marker: sticky.marker)
                        }
                }
                Section("カテゴリ") {
                    ForEach(StickyColor.allCases, id: \.self) { c in
                        Button {
                            sticky.color = c
                            lastColor = c.rawValue
                        } label: {
                            HStack {
                                CategoryLabel(color: c)
                                Spacer()
                                if sticky.color == c {
                                    Image(systemName: "checkmark").foregroundStyle(c.ink)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button("削除", role: .destructive) {
                        context.delete(sticky)
                        dismiss()
                    }
                }
            }
            .navigationTitle("p.\(sticky.pageNumber) の付箋")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 部品

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ u: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onImage(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onImage(nil)
        }
    }
}
