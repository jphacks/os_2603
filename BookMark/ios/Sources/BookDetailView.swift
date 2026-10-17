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
    @State private var showMastered = false

    // 剥がしフロー
    @State private var peelQuizSticky: Sticky?
    @State private var trashSticky: Sticky?
    @State private var undoSticky: Sticky?
    @State private var showUndo = false

    private var placed: [Sticky] {
        book.stickies
            .filter { $0.placed && !$0.mastered }
            .sorted { ($0.pageNumber, $0.order) < ($1.pageNumber, $1.order) }
    }

    private var masteredCount: Int { book.stickies.filter { $0.mastered }.count }
    private var totalPlaced: Int { book.stickies.filter { $0.placed }.count }

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
        .sheet(item: $peelQuizSticky) { sticky in
            PeelQuizView(
                sticky: sticky,
                onMastered: {
                    peelQuizSticky = nil
                    trashSticky = sticky
                },
                onReturn: {
                    peelQuizSticky = nil
                }
            )
            .presentationDetents([.large])
        }
        .fullScreenCover(item: $trashSticky) { sticky in
            TrashGameView(
                sticky: sticky,
                onSuccess: { markMastered(sticky) },
                onDismiss: {
                    trashSticky = nil
                    markMastered(sticky)  // スキップしても覚えた扱い
                }
            )
        }
        .sheet(isPresented: $showMastered) {
            MasteredView(book: book)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                showCamera = false
                if let img { setPhoto(img) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showFlip) {
            FlipView(
                stickies: placed,
                bookTitle: book.title,
                onMastered: { s in markMastered(s) },
                onClose: { showFlip = false })
        }
        .fullScreenCover(isPresented: $showReview) {
            ReviewView(
                stickies: placed,
                onMastered: { s in markMastered(s) },
                onClose: { showReview = false })
        }
        .onChange(of: pickerItem) { _, newItem in loadPicked(newItem) }
        .onAppear { AppStore.lastBookId = book.id.uuidString }
        .overlay(alignment: .bottom) { undoToast }
    }

    // MARK: - 剥がし処理

    private func handlePeel(_ sticky: Sticky) {
        peelQuizSticky = sticky
    }

    private func markMastered(_ sticky: Sticky) {
        sticky.mastered = true
        sticky.masteredAt = .now
        trashSticky = nil
        undoSticky = sticky
        withAnimation { showUndo = true }
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            await MainActor.run {
                withAnimation { showUndo = false }
            }
        }
    }

    @ViewBuilder private var undoToast: some View {
        if showUndo, let s = undoSticky {
            HStack(spacing: 12) {
                Text("付箋を剥がしました")
                    .font(.subheadline)
                Spacer()
                Button("元に戻す") {
                    s.mastered = false; s.masteredAt = nil
                    withAnimation { showUndo = false }
                }
                .font(.subheadline).bold()
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(.black.opacity(0.88))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16).padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - 撮影・一覧

    private var captureAndList: some View {
        ScrollView {
            VStack(spacing: 12) {
                // 撮影ボタン群
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

                Text("囲んで拡大し、確認してから付箋を追加")
                    .font(.caption).foregroundStyle(.secondary)

                // 付箋数・覚えた数
                if totalPlaced > 0 {
                    HStack {
                        Text("付箋 \(totalPlaced) 枚中 \(masteredCount) 枚を覚えた")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if masteredCount > 0 {
                            Button("覚えた付箋を見る") { showMastered = true }
                                .font(.caption).foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // パラパラ・復習
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

                // 書き出しボタン
                ExportButton(book: book)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .disabled(placed.isEmpty)
                    .padding(.top, 2)

                // 付箋一覧（剥がし対応）
                if placed.isEmpty {
                    ContentUnavailableView(
                        "まだ付箋がありません",
                        systemImage: "tag",
                        description: Text("撮って、貼りたい部分を囲んでみましょう"))
                        .padding(.top, 30)
                } else {
                    ForEach(placed) { s in
                        StickyRow(sticky: s)
                            .peelable { handlePeel(s) }
                            .onTapGesture { editing = s }
                    }
                }
            }
            .padding(16)
        }
    }

    private func setPhoto(_ image: UIImage) {
        pageNumber = AppStore.lastPage(for: book.id)
        photo = uprightImage(image)
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

// MARK: - 写真ビュー（なぞって囲む → 範囲OCR → 付箋）

struct PhotoReaderView: View {
    @Environment(\.modelContext) private var context
    let image: UIImage
    @Binding var pageNumber: Int?
    @Bindable var book: Book
    var onEdit: (Sticky) -> Void
    var onClose: () -> Void

    @State private var pageText = ""
    @FocusState private var pageFieldFocused: Bool
    @State private var wholeLines: [OCRLine] = []
    @State private var wholeLoaded = false
    @State private var cachedPins: [UUID: CGRect] = [:]
    // 作成直後は照合せず、選択した位置へそのままピンを置く。
    @State private var localPins: [UUID: CGRect] = [:]
    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    @State private var selectedRect: CGRect?
    @State private var draft: OCRSelection?
    @State private var draftPage: Int?
    @State private var busy = false
    @State private var recognitionTask: Task<Void, Never>?
    @State private var recognitionID: UUID?
    @State private var message: String?
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var activeStickies: [Sticky] {
        book.stickies.filter { $0.placed && !$0.mastered && $0.pageNumber == pageNumber }
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            GeometryReader { geo in
                let ratio = image.size.width / max(image.size.height, 1)
                let w = min(geo.size.width, geo.size.height * ratio)
                let h = w / ratio
                imageCanvas(w: w, h: h)
                    .frame(width: w, height: h)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 16)

            if selectedRect != nil {
                selectionControls
            } else {
                Text(busy ? "ページを読み取り中…" : "囲んで拡大 → 確認して付箋を追加。ピンをタップするとメモが開きます")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 12)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") { pageFieldFocused = false }
            }
        }
        .onAppear {
            if let pn = pageNumber { pageText = String(pn) }
            haptic.prepare()
            if !activeStickies.isEmpty { loadWholePage() }
        }
        .onDisappear { cancelSelection() }
        .onChange(of: pageNumber) { _, _ in
            cancelSelection()
            updateCachedPins()
            if !activeStickies.isEmpty { loadWholePage() }
        }
        .onChange(of: activeStickies.map { $0.id }) { _, _ in updateCachedPins() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("ページ").font(.caption).bold()
            TextField("例)12", text: $pageText)
                .frame(width: 56).textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad).focused($pageFieldFocused)
                .disabled(selectedRect != nil)
                .onChange(of: pageText) { _, value in
                    pageNumber = Int(value.filter { $0.isNumber })
                    if let pn = pageNumber { AppStore.setLastPage(pn, for: book.id) }
                }
            Spacer()
            if !wholeLoaded && selectedRect == nil {
                Button("全体を読む") { loadWholePage() }
                    .font(.caption).disabled(busy)
            }
            Button("閉じる") { onClose() }.buttonStyle(.bordered)
        }
        .padding(.horizontal, 16).padding(.top, 12)
    }

    private var selectionControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "viewfinder")
                Text("選択した部分を確認").font(.subheadline).bold()
                Spacer()
                if busy { ProgressView().controlSize(.small) }
            }
            if let draft {
                Text(draft.marker).font(.caption).lineLimit(3)
                    .foregroundStyle(.secondary)
            } else {
                Text(busy ? "文字を読み取っています…" : "読み取れませんでした。選び直すか再試行してください")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("選び直す") { cancelSelection() }
                    .buttonStyle(.bordered)
                Spacer()
                if draft == nil && !busy {
                    Button("再試行") {
                        if let rect = selectedRect, let pn = draftPage { recognizeSelection(rect, page: pn) }
                    }.buttonStyle(.bordered)
                } else {
                    Button { confirmSelection() } label: {
                        Label("付箋を追加", systemImage: "pin.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.75, green: 0.26, blue: 0.17))
                    .disabled(draft == nil || busy)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func imageCanvas(w: CGFloat, h: CGFloat) -> some View {
        // 選択枠と写真に同じ変換を適用し、選択箇所を画面中央へ拡大する。
        let scale: CGFloat = selectedRect.map { min(5, max(1, min(0.82 / $0.width, 0.72 / $0.height))) } ?? 1
        let offset = selectedRect.map {
            CGSize(width: (0.5 - $0.midX) * w * scale,
                   height: (0.5 - $0.midY) * h * scale)
        } ?? .zero
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().frame(width: w, height: h)
                if let rect = selectedRect {
                    selectionOutline(rect, w: w, h: h, scale: scale)
                } else if let start = dragStart, let end = dragEnd {
                    let rect = normalizedRect(start: start, end: end, w: w, h: h)
                    selectionOutline(rect, w: w, h: h, scale: 1)
                }
            }
            .frame(width: w, height: h)
            .scaleEffect(scale)
            .offset(offset)
            .allowsHitTesting(false)

            // 写真の座標系に固定した操作面。ピンのボタンとは別レイヤー。
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard selectedRect == nil, !busy else { return }
                        if dragStart == nil {
                            pageFieldFocused = false
                            dragStart = value.startLocation
                        }
                        dragEnd = value.location
                    }
                    .onEnded { value in
                        defer { dragStart = nil; dragEnd = nil }
                        guard selectedRect == nil, !busy else { return }
                        let rect = normalizedRect(start: dragStart ?? value.startLocation,
                                                  end: value.location, w: w, h: h)
                        guard rect.width * w > 12, rect.height * h > 8 else { return }
                        guard let pn = pageNumber, pn > 0 else {
                            message = "ページ番号を入力してください"; return
                        }
                        message = nil
                        draftPage = pn
                        withAnimation(.easeInOut(duration: 0.25)) { selectedRect = rect }
                        haptic.impactOccurred()
                        recognizeSelection(rect, page: pn)
                    })

            if selectedRect == nil {
                ForEach(activeStickies) { sticky in
                    if let rect = localPins[sticky.id] ?? cachedPins[sticky.id] {
                        Button { onEdit(sticky) } label: {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.black.opacity(0.8))
                                .frame(width: 28, height: 28)
                                .background(sticky.color.color, in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white, lineWidth: 2))
                                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("付箋: \(sticky.heading)")
                        .accessibilityHint("タップしてメモを開く")
                        .position(x: min(max(22, rect.maxX * w), w - 22),
                                  y: min(max(22, rect.minY * h), h - 22))
                    }
                }
            }
        }
        .frame(width: w, height: h)
    }

    private func selectionOutline(_ rect: CGRect, w: CGFloat, h: CGFloat, scale: CGFloat) -> some View {
        Rectangle().fill(Color.yellow.opacity(0.18))
            .overlay(Rectangle().strokeBorder(Color.orange, lineWidth: 2 / scale))
            .frame(width: max(2, rect.width * w), height: max(2, rect.height * h))
            .position(x: rect.midX * w, y: rect.midY * h)
    }

    private func normalizedRect(start: CGPoint, end: CGPoint, w: CGFloat, h: CGFloat) -> CGRect {
        let x1 = min(max(start.x / max(w, 1), 0), 1)
        let y1 = min(max(start.y / max(h, 1), 0), 1)
        let x2 = min(max(end.x / max(w, 1), 0), 1)
        let y2 = min(max(end.y / max(h, 1), 0), 1)
        return CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
    }

    private func recognizeSelection(_ rect: CGRect, page: Int) {
        guard !busy else { return }
        if wholeLoaded, let selection = OCRSelection.extract(from: wholeLines, in: rect, requireWholeLines: true) {
            draft = selection
            return
        }
        busy = true
        let id = UUID()
        recognitionID = id
        recognitionTask = Task { @MainActor in
            let result = await OCR.recognize(image, regionOfInterest: OCRSelection.expandedRegion(for: rect))
            guard !Task.isCancelled, recognitionID == id else { return }
            busy = false
            recognitionTask = nil
            recognitionID = nil
            guard pageNumber == page, selectedRect == rect else { return }
            draft = OCRSelection.extract(from: result.lines, in: rect)
        }
    }

    private func confirmSelection() {
        guard !busy, let draft, let rect = selectedRect,
              let page = draftPage, pageNumber == page else { return }
        let sticky = Sticky(pageNumber: page, placed: true, marker: draft.marker,
                            clipBefore: draft.before, clipAfter: draft.after,
                            color: StickyColor.cycle(book.stickies.count), book: book)
        context.insert(sticky)
        localPins[sticky.id] = rect
        AppStore.setLastPage(page, for: book.id)
        AIHelper.improveHeading(for: sticky)
        cancelSelection()
        haptic.impactOccurred()
        onEdit(sticky)
    }

    private func cancelSelection() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionID = nil
        busy = false
        draft = nil
        draftPage = nil
        dragStart = nil
        dragEnd = nil
        withAnimation(.easeInOut(duration: 0.2)) { selectedRect = nil }
    }

    private func updateCachedPins() {
        guard wholeLoaded else { cachedPins = [:]; return }
        let texts = wholeLines.map { $0.text }
        var pins: [UUID: CGRect] = [:]
        for sticky in activeStickies where localPins[sticky.id] == nil {
            if let index = findBestLine(marker: sticky.marker, lines: texts) {
                pins[sticky.id] = wholeLines[index].rect
            }
        }
        cachedPins = pins
    }

    private func loadWholePage() {
        guard !wholeLoaded, !busy, selectedRect == nil else { return }
        busy = true
        let id = UUID()
        recognitionID = id
        recognitionTask = Task { @MainActor in
            let result = await OCR.recognize(image)
            guard !Task.isCancelled, recognitionID == id else { return }
            recognitionTask = nil
            recognitionID = nil
            wholeLines = result.lines
            wholeLoaded = !result.lines.isEmpty
            busy = false
            if pageNumber == nil, let pn = result.pageNumber {
                pageNumber = pn; pageText = String(pn)
            }
            updateCachedPins()
            if result.lines.isEmpty { message = "文字が読み取れませんでした。もう一度お試しください" }
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
                            AIHelper.improveHeading(for: sticky)
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
                        context.delete(sticky); dismiss()
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

func uprightImage(_ image: UIImage) -> UIImage {
    guard image.imageOrientation != .up else { return image }
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = image.scale
    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
    return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: image.size))
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
