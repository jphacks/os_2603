import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct BookDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var book: Book

    @State private var photo: UIImage?
    @State private var pageNumber: Int?
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
            if let photo {
                PhotoReaderView(
                    image: photo,
                    pageNumber: $pageNumber,
                    book: book,
                    onEdit: { editing = $0 },
                    onClose: { self.photo = nil })
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
                showCamera = false
                if let img { setPhoto(img) }
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
        .onAppear { AppStore.lastBookId = book.id.uuidString }
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

                Button { setPhoto(Sample.render(Sample.pages[0])) } label: {
                    Label("サンプル画像で試す", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CaptureButton(ghost: true))

                Text("📸 撮ったら、付箋を貼りたい部分を指でなぞって囲むだけ")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button { showFlip = true } label: {
                        Label("パラパラ", systemImage: "book").frame(maxWidth: .infinity)
                    }
                    Button { showReview = true } label: {
                        Label("復習", systemImage: "brain.head.profile").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered).tint(.secondary)
                .disabled(placed.isEmpty)
                .padding(.top, 2)

                if placed.isEmpty {
                    ContentUnavailableView(
                        "まだ付箋がありません",
                        systemImage: "tag",
                        description: Text("撮って、貼りたい部分を囲んでみましょう"))
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

    // 撮影/選択した画像を開く。ページ番号は前回の値を初期値に（開いてから付箋までを短く）。
    private func setPhoto(_ image: UIImage) {
        pageNumber = AppStore.lastPage(for: book.id)
        photo = image
    }

    private func loadPicked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                await MainActor.run { setPhoto(img) }
            }
            await MainActor.run { pickerItem = nil }
        }
    }
}

// MARK: - 写真ビュー（なぞって囲む → その範囲だけOCR → 付箋）

struct PhotoReaderView: View {
    @Environment(\.modelContext) private var context
    let image: UIImage
    @Binding var pageNumber: Int?
    @Bindable var book: Book
    var onEdit: (Sticky) -> Void
    var onClose: () -> Void

    @State private var pageText = ""
    @State private var wholeLines: [OCRLine] = []   // 復元/タップ補助（必要時のみ全体を読む）
    @State private var wholeLoaded = false
    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    @State private var busy = false
    @State private var flash: CGRect?               // 作成直後の軽いハイライト（正規化）
    @State private var message: String?

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    private var lineTexts: [String] { wholeLines.map { $0.text } }

    private var anchors: [Int: Sticky] {
        guard wholeLoaded, let pn = pageNumber else { return [:] }
        var map: [Int: Sticky] = [:]
        for s in book.stickies where s.placed && s.pageNumber == pn {
            if let i = findBestLine(marker: s.marker, lines: lineTexts) { map[i] = s }
        }
        return map
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            GeometryReader { geo in
                let w = geo.size.width
                let h = w * image.size.height / max(image.size.width, 1)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image).resizable().frame(width: w, height: h)

                    if wholeLoaded {
                        ForEach(Array(wholeLines.enumerated()), id: \.element.id) { idx, line in
                            let r = line.rect
                            let st = anchors[idx]
                            Rectangle()
                                .fill((st?.color.color ?? .clear).opacity(st == nil ? 0.001 : 0.35))
                                .overlay(alignment: .trailing) {
                                    if let s = st {
                                        Text(String(repeating: "★", count: s.importance))
                                            .font(.system(size: 9)).bold()
                                            .padding(.horizontal, 3)
                                            .background(s.color.color)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                            .offset(x: 6)
                                    }
                                }
                                .frame(width: r.width * w, height: max(r.height * h, 16))
                                .contentShape(Rectangle())
                                .position(x: (r.minX + r.width / 2) * w, y: (r.minY + r.height / 2) * h)
                                .onTapGesture { tapLine(idx) }
                        }
                    }

                    if let start = dragStart, let end = dragEnd {
                        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                          width: abs(end.x - start.x), height: abs(end.y - start.y))
                        Rectangle()
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .background(Color.accentColor.opacity(0.12))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                    }

                    if let f = flash {
                        Rectangle().fill(Color.yellow.opacity(0.45))
                            .frame(width: f.width * w, height: f.height * h)
                            .position(x: (f.minX + f.width / 2) * w, y: (f.minY + f.height / 2) * h)
                            .allowsHitTesting(false)
                    }

                    if busy {
                        Color.black.opacity(0.05).frame(width: w, height: h)
                        ProgressView().position(x: w / 2, y: h / 2)
                    }
                }
                .frame(width: w, height: h)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { v in
                            if dragStart == nil { dragStart = v.startLocation }
                            dragEnd = v.location
                        }
                        .onEnded { v in
                            let start = dragStart ?? v.startLocation
                            finishDrag(start: start, end: v.location, w: w, h: h)
                            dragStart = nil; dragEnd = nil
                        }
                )
            }
            .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
            .padding(.horizontal, 16)

            Text(pageNumber == nil
                 ? "ページ番号を入れてから、貼りたい部分を囲んでください"
                 : "貼りたい部分を指でなぞって囲む（行をタップでも可）")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            if let message {
                Text(message).font(.caption).foregroundStyle(Color(red: 0.75, green: 0.26, blue: 0.17))
            }
            Spacer(minLength: 0)
        }
        .onAppear {
            if let pn = pageNumber { pageText = String(pn) }
            haptic.prepare()
            // 既存付箋のあるページだけ、復元のため全体を読む（許可された例外）
            if let pn = pageNumber,
               book.stickies.contains(where: { $0.placed && $0.pageNumber == pn }) {
                loadWholePage()
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "number")
                Text("ページ")
                TextField("例)12", text: $pageText)
                    .frame(width: 56)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .onChange(of: pageText) { _, v in
                        pageNumber = Int(v.filter { $0.isNumber })
                        if let pn = pageNumber {
                            AppStore.setLastPage(pn, for: book.id)
                            // そのページに既存付箋があれば、復元のため全体を読む（許可された例外）
                            if !wholeLoaded,
                               book.stickies.contains(where: { $0.placed && $0.pageNumber == pn }) {
                                loadWholePage()
                            }
                        }
                    }
            }
            .font(.footnote).bold()
            Spacer()
            if !wholeLoaded {
                Button {
                    loadWholePage()
                } label: { Label("全体を読む", systemImage: "text.viewfinder").font(.footnote) }
                .buttonStyle(.bordered).tint(.secondary)
            }
            Button("閉じる") { onClose() }.buttonStyle(.bordered)
        }
        .padding(.horizontal, 16).padding(.top, 12)
    }

    // 囲んだ範囲だけOCR（周辺の行は clip 用に少し広げて読む）。
    private func finishDrag(start: CGPoint, end: CGPoint, w: CGFloat, h: CGFloat) {
        let vx = min(start.x, end.x), vy = min(start.y, end.y)
        let vw = abs(end.x - start.x), vh = abs(end.y - start.y)
        guard vw > 12, vh > 8 else { return }       // 小さすぎる操作は無視
        guard let pn = pageNumber else {
            show("ページ番号を入れてください"); return
        }
        let rect = CGRect(x: vx / w, y: vy / h, width: vw / w, height: vh / h)

        busy = true
        message = nil
        Task {
            // clip 用に上下を少し広げる
            let pad = max(0.03, Double(rect.height) * 0.9)
            let expanded = CGRect(
                x: max(0, rect.minX - 0.02),
                y: max(0, rect.minY - pad),
                width: min(1, rect.width + 0.04),
                height: min(1, rect.height + pad * 2))
            let lines = await OCR.recognize(image, regionOfInterest: expanded).lines

            func centerY(_ l: OCRLine) -> CGFloat { l.rect.midY }
            let sel = lines.filter { centerY($0) >= rect.minY && centerY($0) <= rect.maxY }
            let before = lines.filter { centerY($0) < rect.minY }
            let after = lines.filter { centerY($0) > rect.maxY }

            let markerLines = sel.isEmpty ? lines : sel
            let marker = markerLines.map { $0.text }.joined().trimmingCharacters(in: .whitespacesAndNewlines)

            await MainActor.run {
                busy = false
                guard !marker.isEmpty else { show("文字が読み取れませんでした"); return }
                let clipBefore = before.suffix(2).map { $0.text }
                let clipAfter = after.prefix(2).map { $0.text }
                createSticky(pageNumber: pn, marker: marker,
                             clipBefore: clipBefore, clipAfter: Array(clipAfter))
                flashRect(rect)
            }
        }
    }

    // 行をタップ（補助）。全体を読んである時だけ有効。
    private func tapLine(_ i: Int) {
        if let s = anchors[i] { onEdit(s); return }
        guard let pn = pageNumber else { show("ページ番号を入れてください"); return }
        let texts = lineTexts
        if normalizeText(texts[i]).isEmpty { return }
        let before = Array(texts[max(0, i - 2)..<i])
        let after = Array(texts[(i + 1)..<min(texts.count, i + 3)])
        createSticky(pageNumber: pn, marker: texts[i], clipBefore: before, clipAfter: after)
    }

    private func createSticky(pageNumber pn: Int, marker: String,
                              clipBefore: [String], clipAfter: [String]) {
        let color = StickyColor.cycle(book.stickies.count)
        let sticky = Sticky(
            pageNumber: pn, placed: true, marker: marker,
            clipBefore: clipBefore, clipAfter: clipAfter, color: color, book: book)
        context.insert(sticky)
        AppStore.setLastPage(pn, for: book.id)
        haptic.impactOccurred()       // 触覚フィードバック
    }

    private func loadWholePage() {
        guard !wholeLoaded else { return }
        busy = true
        Task {
            let result = await OCR.recognize(image)
            await MainActor.run {
                wholeLines = result.lines
                wholeLoaded = true
                if pageNumber == nil, let pn = result.pageNumber {
                    pageNumber = pn; pageText = String(pn)
                }
                busy = false
            }
        }
    }

    private func flashRect(_ rect: CGRect) {
        flash = rect
        Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            await MainActor.run { flash = nil }
        }
    }

    private func show(_ text: String) {
        message = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { if message == text { message = nil } }
        }
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
                    Text(sticky.heading).font(.headline).lineLimit(1)
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
