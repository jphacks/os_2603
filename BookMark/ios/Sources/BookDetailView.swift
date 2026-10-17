import SwiftUI
import SwiftData
import PhotosUI

struct BookDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var book: Book

    @State private var photo: UIImage?
    @State private var ocr: OCRResult?
    @State private var pageNumber: Int?
    @State private var recognizing = false
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var editing: Sticky?
    @State private var showFlip = false
    @State private var showReview = false

    private var placed: [Sticky] {
        book.stickies.filter { $0.placed }
            .sorted { ($0.pageNumber, $0.order) < ($1.pageNumber, $1.order) }
    }

    var body: some View {
        Group {
            if recognizing {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("文字を認識中…").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let photo, let ocr {
                PhotoReaderView(
                    image: photo, ocr: ocr, pageNumber: $pageNumber,
                    book: book,
                    onEdit: { editing = $0 },
                    onClose: { clearPhoto() })
            } else {
                captureAndList
            }
        }
        .background(Color(red: 0.969, green: 0.957, blue: 0.925))
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { StickyEditor(sticky: $0) }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                showCamera = false          // 撮影/キャンセル後にカメラを閉じる
                if let img { runOCR(img) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showFlip) {
            FlipView(stickies: placed, bookTitle: book.title) { showFlip = false }
        }
        .fullScreenCover(isPresented: $showReview) {
            ReviewView(stickies: placed) { showReview = false }
        }
        .onChange(of: pickerItem) { _, newItem in loadPicked(newItem) }
    }

    private var captureAndList: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: {
                            Label("カメラで撮る", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CaptureButton())
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("写真を選ぶ", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CaptureButton())
                }

                Button { runSample() } label: {
                    Label("サンプル画像でOCR", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CaptureButton(ghost: true))

                Text("📸 コツ: 片方のページだけを正面から・明るく・なるべく平らに")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button { showFlip = true } label: {
                        Label("パラパラ", systemImage: "book")
                            .frame(maxWidth: .infinity)
                    }
                    Button { showReview = true } label: {
                        Label("復習", systemImage: "brain.head.profile")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .disabled(placed.isEmpty)
                .padding(.top, 2)

                if placed.isEmpty {
                    ContentUnavailableView(
                        "まだ付箋がありません",
                        systemImage: "tag",
                        description: Text("写真を撮って行をタップしてみましょう"))
                        .padding(.top, 30)
                } else {
                    ForEach(placed) { s in
                        Button { editing = s } label: { StickyRow(sticky: s) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
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
                                        Text(String(repeating: "★", count: s.importance))
                                            .font(.system(size: 9)).bold()
                                            .padding(.horizontal, 3)
                                            .background(s.color.color)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                            .offset(x: 6)
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
                    .font(.caption).foregroundStyle(.secondary)
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
        let color = StickyColor.cycle(book.stickies.count)
        let sticky = Sticky(
            pageNumber: pn, placed: true, marker: texts[i],
            clipBefore: before, clipAfter: after, color: color, book: book)
        context.insert(sticky)
    }
}

// MARK: - 付箋の行

struct StickyRow: View {
    let sticky: Sticky
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4).fill(sticky.color.color).frame(width: 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(sticky.heading).font(.headline)
                    Text("p.\(sticky.pageNumber)")
                        .font(.caption2).bold().foregroundStyle(.secondary)
                    Text(String(repeating: "★", count: sticky.importance))
                        .font(.caption2).foregroundStyle(Color(red: 0.75, green: 0.26, blue: 0.17))
                }
                Text(sticky.marker).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !sticky.memo.isEmpty {
                    Text("📝 \(sticky.memo)").font(.caption)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 1.0, green: 0.992, blue: 0.973))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08)))
    }
}

// MARK: - 付箋編集

struct StickyEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var sticky: Sticky

    var body: some View {
        NavigationStack {
            Form {
                Section("目印") {
                    Text(sticky.marker).font(.subheadline)
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
                Section("色") {
                    HStack(spacing: 12) {
                        ForEach(StickyColor.allCases, id: \.self) { c in
                            Circle().fill(c.color).frame(width: 32, height: 32)
                                .overlay(Circle().stroke(.primary, lineWidth: sticky.color == c ? 2 : 0))
                                .onTapGesture { sticky.color = c }
                        }
                    }
                }
                Section("重要度") {
                    Picker("重要度", selection: $sticky.importance) {
                        Text("★").tag(1); Text("★★").tag(2); Text("★★★").tag(3)
                    }.pickerStyle(.segmented)
                }
                Section {
                    Button("削除", role: .destructive) {
                        context.delete(sticky)
                        dismiss()
                    }
                }
            }
            .navigationTitle("付箋")
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

struct CaptureButton: ButtonStyle {
    var ghost = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline).bold()
            .padding(.vertical, 14)
            .foregroundStyle(ghost ? Color.secondary : .white)
            .background(ghost ? Color(red: 1.0, green: 0.992, blue: 0.973)
                              : Color(red: 0.75, green: 0.26, blue: 0.17))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(ghost ? 0.12 : 0)))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

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
