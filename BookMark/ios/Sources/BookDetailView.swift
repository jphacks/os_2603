import AVFoundation
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
    @State private var showQuickMemo = false

    @State private var showCameraAlert = false
    @State private var undoSticky: Sticky?
    @State private var showUndo = false

    private var placed: [Sticky] {
        book.stickies
            .filter { $0.placed && !$0.mastered }
            .sorted { ($0.pageNumber, $0.order) < ($1.pageNumber, $1.order) }
    }

    private var masteredCount: Int { book.stickies.filter { $0.mastered }.count }
    private var totalPlaced: Int { book.stickies.filter { $0.placed }.count }

    // ページごとの付箋グループ（小口ビューからのスクロール用）
    private var placedByPage: [(page: Int, stickies: [Sticky])] {
        let dict = Dictionary(grouping: placed) { $0.pageNumber }
        return dict.keys.sorted().map { ($0, dict[$0]!) }
    }

    // 位置未定のメモ（A5：写真なしで先に残したメモ）
    private var unplacedMemos: [Sticky] {
        book.stickies.filter { !$0.placed && !$0.mastered }
            .sorted { $0.pageNumber < $1.pageNumber }
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
        .background(BooksStyle.background)
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { StickyEditor(sticky: $0) }
        .sheet(isPresented: $showMastered) {
            MasteredView(book: book)
        }
        .sheet(isPresented: $showQuickMemo) {
            QuickMemoSheet(book: book, defaultPage: pageNumber ?? AppStore.lastPage(for: book.id))
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                showCamera = false
                if let img { setPhoto(img) }
            }
            .ignoresSafeArea()
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
                onClose: { showReview = false })
        }
        .onChange(of: pickerItem) { _, newItem in loadPicked(newItem) }
        .onAppear { AppStore.lastBookId = book.id.uuidString }
        .overlay(alignment: .bottom) { undoToast }
    }

    private func markMastered(_ sticky: Sticky) {
        sticky.mastered = true
        sticky.masteredAt = .now
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
                Text("覚えました")
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
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 14) {
                // 表紙・書名・著者（Apple Books の本の詳細のように中央に大きく）
                VStack(spacing: 10) {
                    BookCoverView(book: book, titleFont: .system(size: 17, weight: .heavy))
                        .frame(width: 150)
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
                    Text(book.title)
                        .font(.title2.bold())
                        .foregroundStyle(BooksStyle.ink)
                        .multilineTextAlignment(.center)
                    if let author = book.author, !author.isEmpty {
                        Text(author).font(.subheadline).foregroundStyle(BooksStyle.subInk)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 6)

                // 撮影ボタン群
                HStack(spacing: 10) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            let status = AVCaptureDevice.authorizationStatus(for: .video)
                            if status == .denied || status == .restricted {
                                showCameraAlert = true
                            } else {
                                showCamera = true
                            }
                        } label: {
                            Label("カメラで撮る", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CaptureButton())
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("写真を選ぶ", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CaptureButton(ghost: UIImagePickerController.isSourceTypeAvailable(.camera)))
                }

                Text("囲んで拡大し、確認してから付箋を追加")
                    .font(.caption).foregroundStyle(BooksStyle.subInk)

                // メモだけモード（A5：撮影せずページ番号＋メモで付箋）
                Button { showQuickMemo = true } label: {
                    Label("メモだけ残す（声でも）", systemImage: "mic.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CaptureButton(ghost: true))

                Divider().padding(.vertical, 6)

                // 位置未定のメモ（後で撮って囲むと配置される）
                if !unplacedMemos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("位置未定のメモ \(unplacedMemos.count)件（撮って囲むと配置）")
                            .font(.caption.weight(.semibold)).foregroundStyle(BooksStyle.accent)
                        ForEach(unplacedMemos) { s in
                            StickyRow(sticky: s).onTapGesture { editing = s }
                        }
                    }
                }

                // 付箋数・覚えた数
                if totalPlaced > 0 {
                    HStack {
                        Text("付箋 \(totalPlaced) 枚中 \(masteredCount) 枚を覚えた")
                            .font(.caption).foregroundStyle(BooksStyle.subInk)
                        Spacer()
                        if masteredCount > 0 {
                            Button("覚えた付箋を見る") { showMastered = true }
                                .font(.caption.weight(.semibold)).foregroundStyle(BooksStyle.accent)
                        }
                    }
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
                .buttonStyle(CaptureButton(ghost: true))
                .disabled(placed.isEmpty)

                // 本の小口ビュー（B2）：タブをタップでそのページへスクロール
                if !placed.isEmpty {
                    BookSpineView(book: book) { pn in
                        withAnimation { proxy.scrollTo("page-\(pn)", anchor: .top) }
                    }
                    .padding(.top, 2)
                }

                // 付箋一覧（ページごと・剥がし対応）
                if placed.isEmpty {
                    ContentUnavailableView(
                        "まだ付箋がありません",
                        systemImage: "tag",
                        description: Text("撮って、貼りたい部分を囲んでみましょう"))
                        .padding(.top, 20)
                } else {
                    ForEach(placedByPage, id: \.page) { group in
                        VStack(spacing: 10) {
                            HStack {
                                Text("p.\(group.page)")
                                    .font(.caption.weight(.semibold)).foregroundStyle(BooksStyle.subInk)
                                Spacer()
                            }
                            ForEach(group.stickies) { s in
                                StickyRow(sticky: s)
                                    .onTapGesture { editing = s }
                                    .peelable(tint: s.color.color) { markMastered(s) }
                            }
                        }
                        .id("page-\(group.page)")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
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
    @State private var manualZoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    @State private var manualOffset: CGSize = .zero
    @State private var moveMode = false
    @State private var panStart: CGSize?
    @State private var pinching = false
    @State private var matchingTask: Task<Void, Never>?
    @State private var matchingID: UUID?
    @State private var restoring = false
    @State private var busy = false
    @State private var recognitionTask: Task<Void, Never>?
    @State private var recognitionID: UUID?
    @State private var message: String?
    @State private var didAutoDetectPage = false
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var activeStickies: [Sticky] {
        book.stickies.filter { $0.placed && !$0.mastered && $0.pageNumber == pageNumber }
    }
    private var pageUnplaced: [Sticky] {
        book.stickies.filter { !$0.placed && !$0.mastered && $0.pageNumber == pageNumber }
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            zoomControls
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
                Text(busy ? "ページを読み取り中…" : "ピンチで拡大。「移動」で位置を合わせ、「範囲選択」で囲みます。ピンをタップするとメモが開きます")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
            if selectedRect == nil && !activeStickies.isEmpty {
                HStack {
                    Text(restoring ? "付箋の位置を復元中…" : "このページの付箋 \(activeStickies.count)枚")
                    Spacer()
                    Menu("付箋一覧") {
                        ForEach(activeStickies) { sticky in
                            Button(sticky.heading) { onEdit(sticky) }
                        }
                    }
                }.font(.caption).padding(.horizontal, 20)
            }
            if selectedRect == nil && !pageUnplaced.isEmpty {
                Text("このページに位置未定のメモが\(pageUnplaced.count)件。囲むと配置されます")
                    .font(.caption).foregroundStyle(BooksStyle.accent)
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
            if book.stickies.contains(where: { $0.placed && !$0.mastered }) { loadWholePage() }
            autoDetectPage()
            // キーボードを裏で事前ロード（初回表示の遅延対策）
            preWarmKeyboard()
        }
        .onDisappear {
            cancelSelection()
            matchingTask?.cancel()
            matchingID = nil
            restoring = false
        }
        .onChange(of: pageNumber) { _, _ in
            cancelSelection()
            updateCachedPins()
            if !activeStickies.isEmpty { loadWholePage() }
        }
        .onChange(of: activeStickies.map { $0.id }) { _, _ in updateCachedPins() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("ページ").font(.caption).bold().fixedSize()
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
            Button("閉じる") { onClose() }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent).tint(BooksStyle.ink)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16).padding(.top, 12)
    }

    private var zoomControls: some View {
        HStack(spacing: 12) {
            Button { manualZoom = max(1, manualZoom - 0.5) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            Text("\(manualZoom, specifier: "%.1f")×").font(.caption.monospacedDigit())
            Button { manualZoom = min(8, manualZoom + 0.5) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            Picker("操作", selection: $moveMode) {
                Text("範囲選択").tag(false)
                Text("移動").tag(true)
            }.pickerStyle(.segmented)
            Button("全体") {
                manualZoom = 1
                manualOffset = .zero
            }.font(.caption)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .disabled(selectedRect != nil)
        .accessibilityHint("ピンチでも拡大できます。移動で位置を合わせ、範囲選択で囲みます")
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
                Text(busy ? "文字を読み取っています…" : "テキストが読み取れませんでした")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("選び直す") { cancelSelection() }
                    .buttonStyle(.bordered)
                Spacer()
                if !busy {
                    if draft == nil {
                        Button("再試行") {
                            if let rect = selectedRect, let pn = draftPage { recognizeSelection(rect, page: pn) }
                        }.buttonStyle(.bordered)
                    }
                    Button { confirmSelection() } label: {
                        Label(draft == nil ? "図として追加" : "付箋を追加", systemImage: "pin.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BooksStyle.ink)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func imageCanvas(w: CGFloat, h: CGFloat) -> some View {
        // 選択枠と写真に同じ変換を適用し、選択箇所を画面中央へ拡大する。
        let scale: CGFloat = selectedRect.map { min(8, max(1, min(0.82 / $0.width, 0.72 / $0.height))) } ?? min(8, max(1, manualZoom * magnification))
        let offset = selectedRect.map {
            CGSize(width: (0.5 - $0.midX) * w * scale,
                   height: (0.5 - $0.midY) * h * scale)
        } ?? manualOffset
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().frame(width: w, height: h)
                    .overlay(Rectangle().stroke(Color.black.opacity(0.08)))
                if let rect = selectedRect {
                    selectionOutline(rect, w: w, h: h, scale: scale)
                } else if let start = dragStart, let end = dragEnd {
                    let rect = normalizedRect(start: start, end: end, w: w, h: h, scale: scale, offset: offset)
                    selectionOutline(rect, w: w, h: h, scale: scale)
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
                        guard selectedRect == nil, !busy, !pinching else { return }
                        if moveMode {
                            if panStart == nil { panStart = manualOffset }
                            manualOffset = CGSize(width: (panStart?.width ?? 0) + value.translation.width,
                                                  height: (panStart?.height ?? 0) + value.translation.height)
                            return
                        }
                        if dragStart == nil {
                            pageFieldFocused = false
                            dragStart = value.startLocation
                        }
                        dragEnd = value.location
                    }
                    .onEnded { value in
                        defer { dragStart = nil; dragEnd = nil; panStart = nil }
                        guard selectedRect == nil, !busy, !pinching, !moveMode else { return }
                        let rect = normalizedRect(start: dragStart ?? value.startLocation,
                                                  end: value.location, w: w, h: h, scale: scale, offset: offset)
                        guard rect.width * w * scale > 12, rect.height * h * scale > 8 else { return }
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
                        .position(x: (rect.maxX - 0.5) * w * scale + w / 2 + offset.width,
                                  y: (rect.minY - 0.5) * h * scale + h / 2 + offset.height)
                    }
                }
            }
        }
        .frame(width: w, height: h)
        .simultaneousGesture(MagnificationGesture()
            .updating($magnification) { value, state, _ in
                if selectedRect == nil { state = value }
            }
            .onChanged { _ in
                guard selectedRect == nil else { return }
                pinching = true
                dragStart = nil; dragEnd = nil
            }
            .onEnded { value in
                if selectedRect == nil { manualZoom = min(8, max(1, manualZoom * value)) }
                // 同時認識しているドラッグの終了を範囲選択として扱わない。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { pinching = false }
            })
    }

    private func selectionOutline(_ rect: CGRect, w: CGFloat, h: CGFloat, scale: CGFloat) -> some View {
        Rectangle().fill(BooksStyle.accent.opacity(0.12))
            .overlay(Rectangle().strokeBorder(BooksStyle.accent, lineWidth: 2 / scale))
            .frame(width: max(2, rect.width * w), height: max(2, rect.height * h))
            .position(x: rect.midX * w, y: rect.midY * h)
    }

    private func normalizedRect(start: CGPoint, end: CGPoint, w: CGFloat, h: CGFloat,
                                scale: CGFloat, offset: CGSize) -> CGRect {
        ReaderCoordinates.selection(start: start, end: end, size: CGSize(width: w, height: h),
                                    scale: scale, offset: offset)
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
        guard !busy, let rect = selectedRect,
              let page = draftPage, pageNumber == page else { return }
        let markerText = draft?.marker ?? "(図)"
        let sticky: Sticky
        // A5：このページに位置未定のメモがあれば、それを配置する（新規作成しない）。
        if let pending = book.stickies
            .filter({ !$0.placed && !$0.mastered && $0.pageNumber == page })
            .min(by: { $0.createdAt < $1.createdAt }) {
            pending.placed = true
            pending.marker = markerText
            pending.clipBefore = draft?.before ?? []
            pending.clipAfter = draft?.after ?? []
            if pending.heading.isEmpty || pending.heading == "付箋" {
                pending.heading = Sticky.makeHeading(memo: "", marker: markerText)
            }
            sticky = pending
        } else {
            sticky = Sticky(pageNumber: page, placed: true, marker: markerText,
                            clipBefore: draft?.before ?? [], clipAfter: draft?.after ?? [],
                            color: StickyColor.cycle(book.stickies.count), book: book)
            context.insert(sticky)
        }
        let markerTrimmed = markerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isQuestion = markerTrimmed.hasSuffix("?") || markerTrimmed.hasSuffix("？")
        sticky.reviewEnabled = isQuestion
        if isQuestion {
            sticky.reviewStyle = "qa"
            NotificationScheduler.scheduleInitial(for: sticky)
        }
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
        matchingTask?.cancel()
        matchingID = nil
        guard wholeLoaded else { cachedPins = [:]; restoring = false; return }
        let texts = wholeLines.map { $0.text }
        let rects = wholeLines.map { $0.rect }
        let markers = activeStickies.filter { localPins[$0.id] == nil }.map { ($0.id, $0.marker) }
        let id = UUID()
        matchingID = id
        restoring = true
        matchingTask = Task { @MainActor in
            // Phase 1: テキスト照合（バックグラウンド）
            let worker = Task.detached(priority: .userInitiated) { () -> [UUID: CGRect] in
                var pins: [UUID: CGRect] = [:]
                for (stickyID, marker) in markers {
                    guard !Task.isCancelled else { return [:] }
                    if let range = findBestPassage(marker: marker, lines: texts) {
                        pins[stickyID] = range.reduce(CGRect.null) { $0.union(rects[$1]) }
                    }
                }
                return pins
            }
            var pins = await withTaskCancellationHandler(operation: { await worker.value },
                                                         onCancel: { worker.cancel() })
            guard !Task.isCancelled, matchingID == id else { return }

                guard !Task.isCancelled, matchingID == id else { return }
            cachedPins = pins
            restoring = false
            matchingTask = nil
            let unmatched = markers.count - pins.count
            message = unmatched > 0 ? "位置を特定できない付箋が\(unmatched)枚あります。ページ番号を確認するか、付箋一覧から開けます" : nil
        }
    }

    // 写真の上下の余白だけを読み、ページ番号を自動で入力する。
    // ページ全体は読まない（プライバシー・速度）。検出できなければ前回値のまま。
    private func autoDetectPage() {
        guard !didAutoDetectPage else { return }
        didAutoDetectPage = true
        let initial = pageText
        Task {
            // 下の余白（ノンブルが多い）→ 上の余白 の順に探す。
            let strips = [CGRect(x: 0, y: 0.82, width: 1, height: 0.18),
                          CGRect(x: 0, y: 0, width: 1, height: 0.18)]
            for roi in strips {
                if Task.isCancelled { return }
                let result = await OCR.recognize(image, regionOfInterest: roi)
                guard let pn = result.pageNumber else { continue }
                await MainActor.run {
                    // ユーザーが手入力/範囲選択を始めていなければ自動反映。
                    guard pageText == initial, selectedRect == nil else { return }
                    pageText = String(pn)
                    pageNumber = pn
                    AppStore.setLastPage(pn, for: book.id)
                    let note = "ページ \(pn) を自動入力しました"
                    message = note
                    Task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        await MainActor.run { if message == note { message = nil } }
                    }
                }
                return
            }
            // ページ番号が見つからなかった場合
            await MainActor.run {
                guard pageText == initial, selectedRect == nil else { return }
                message = "ページ番号を入力してください"
            }
        }
    }

    private func preWarmKeyboard() {
        DispatchQueue.main.async {
            let tf = UITextField(frame: .zero)
            tf.inputView = UIView() // キーボード表示を抑制
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.windows.first?.addSubview(tf)
            tf.becomeFirstResponder()
            tf.resignFirstResponder()
            tf.removeFromSuperview()
        }
    }

    private func loadWholePage() {
        guard !wholeLoaded, !busy, selectedRect == nil else { return }
        busy = true
        let id = UUID()
        let pageAtStart = pageNumber
        recognitionID = id
        recognitionTask = Task { @MainActor in
            let result = await OCR.recognize(image)
            guard !Task.isCancelled, recognitionID == id else { return }
            recognitionTask = nil
            recognitionID = nil
            wholeLines = result.lines
            wholeLoaded = !result.lines.isEmpty
            busy = false
            if pageNumber == pageAtStart, let pn = result.pageNumber {
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
    @Environment(VaultManager.self) private var vault

    private var displayMemo: String {
        if let data = sticky.encryptedMemo { return vault.decrypt(data) ?? "" }
        return sticky.memo
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(sticky.color.color).frame(width: 5)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(sticky.heading).font(.headline).foregroundStyle(BooksStyle.ink).lineLimit(1)
                    Spacer()
                    Text(AppStore.colorName(sticky.color))
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(sticky.color.color.opacity(0.4), in: Capsule())
                        .foregroundStyle(BooksStyle.ink)
                    Text(String(repeating: "★", count: sticky.importance))
                        .font(.caption2).foregroundStyle(BooksStyle.ink)
                    Text("p.\(sticky.pageNumber)")
                        .font(.caption).foregroundStyle(BooksStyle.subInk)
                }
                Text(sticky.marker)
                    .font(BooksStyle.serif(.subheadline))
                    .foregroundStyle(BooksStyle.ink)
                    .padding(.horizontal, 2)
                    .background(sticky.color.color.opacity(0.35))
                    .lineLimit(2)

                if !displayMemo.isEmpty {
                    Text("📝 \(displayMemo)").font(.caption).foregroundStyle(BooksStyle.subInk)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BooksStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 付箋編集

struct StickyEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(VaultManager.self) private var vault
    @Bindable var sticky: Sticky
    @State private var memoText: String = ""
    @State private var colorNameText: String = ""
    @State private var encryptTask: Task<Void, Never>?
    @State private var summarizing = false
    @State private var summaryMessage: String?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("要点") {
                    if let summary = sticky.summarizedText, !summary.isEmpty {
                        Text(summary).font(.body).textSelection(.enabled)
                        Text("端末内AIによる要約。原文と照らし合わせて確認できます")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(sticky.heading).font(.headline)
                        Text(sticky.marker).font(.subheadline).lineLimit(3)
                    }
                    if AIHelper.isAvailable {
                        Button {
                            Task { await summarize() }
                        } label: {
                            HStack {
                                if summarizing { ProgressView() }
                                Label(summarizing ? "要点を整理中…" : "端末内AIで整理", systemImage: "sparkles")
                            }
                        }.disabled(summarizing)
                    } else {
                        Text("この端末ではAI要約を利用できません。原文は下から確認できます")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let summaryMessage { Text(summaryMessage).font(.caption).foregroundStyle(.secondary) }
                }
                Section {
                    DisclosureGroup("原文と前後の文章") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sticky.clipBefore.joined(separator: "\n")).foregroundStyle(.secondary)
                            Text(sticky.marker).textSelection(.enabled)
                            Text(sticky.clipAfter.joined(separator: "\n")).foregroundStyle(.secondary)
                        }.font(.subheadline)
                    }
                }
                Section("メモ") {
                    TextField("気づいたこと・覚えたいこと", text: $memoText, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: memoText) { _, v in
                            sticky.heading = Sticky.makeHeading(memo: v, marker: sticky.marker)
                            // メモ末尾が ? なら復習対象に自動設定
                            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
                            let isQ = trimmed.hasSuffix("?") || trimmed.hasSuffix("？")
                            if isQ != sticky.reviewEnabled {
                                sticky.reviewEnabled = isQ
                                sticky.reviewStyle = isQ ? "qa" : nil
                                if isQ { NotificationScheduler.scheduleInitial(for: sticky) }
                                else   { NotificationScheduler.cancel(stickyID: sticky.id) }
                            }
                            encryptTask?.cancel()
                            encryptTask = Task {
                                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒待つ
                                guard !Task.isCancelled else { return }
                                if let encrypted = vault.encrypt(v) {
                                    sticky.encryptedMemo = encrypted
                                    sticky.memo = ""
                                }
                            }
                        }

                }
                Section("色") {
                    HStack(spacing: 12) {
                        ForEach(StickyColor.allCases, id: \.self) { c in
                            VStack(spacing: 4) {
                                Circle().fill(c.color).frame(width: 32, height: 32)
                                    .overlay(Circle().stroke(.primary, lineWidth: sticky.color == c ? 2 : 0))
                                Text(AppStore.colorName(c))
                                    .font(.caption2)
                                    .foregroundStyle(sticky.color == c ? BooksStyle.ink : BooksStyle.subInk)
                            }
                            .onTapGesture {
                                sticky.color = c
                                colorNameText = AppStore.colorName(c)
                            }
                        }
                    }
                    HStack {
                        Text("この色の名前").font(.caption).foregroundStyle(.secondary)
                        TextField("例）重要", text: $colorNameText)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: colorNameText) { _, v in
                                AppStore.setColorName(v, for: sticky.color)
                            }
                    }
                }
                Section("重要度") {
                    Picker("重要度", selection: $sticky.importance) {
                        Text("★").tag(1); Text("★★").tag(2); Text("★★★").tag(3)
                    }.pickerStyle(.segmented)
                }
                Section {
                    Toggle("復習対象にする", isOn: Binding(
                        get: { sticky.reviewEnabled },
                        set: { enabled in
                            sticky.reviewEnabled = enabled
                            if enabled {
                                sticky.reviewStyle = "qa"
                                NotificationScheduler.scheduleInitial(for: sticky)
                            } else {
                                sticky.reviewStyle = nil
                                NotificationScheduler.cancel(stickyID: sticky.id)
                            }
                        }
                    ))
                }
            }
            .onAppear {
                if let data = sticky.encryptedMemo {
                    memoText = vault.decrypt(data) ?? sticky.memo
                } else {
                    memoText = sticky.memo
                }
                colorNameText = AppStore.colorName(sticky.color)
            }
            .task(id: sticky.id) {
                if sticky.summarizedText == nil { await summarize() }
            }
            .navigationTitle("付箋")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("削除", role: .destructive) { showDeleteConfirm = true }
                        .tint(.red)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .confirmationDialog("この付箋を削除しますか？", isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("削除する", role: .destructive) { context.delete(sticky); dismiss() }
                Button("キャンセル", role: .cancel) {}
            }
        }
    }
    @MainActor private func summarize() async {
        guard !summarizing, AIHelper.isAvailable else { return }
        summarizing = true
        summaryMessage = nil
        defer { summarizing = false }
        let marker = sticky.marker
        let result = await AIHelper.summarize(marker: marker, before: sticky.clipBefore, after: sticky.clipAfter)
        guard !Task.isCancelled, sticky.modelContext != nil, sticky.marker == marker else { return }
        if let result { sticky.summarizedText = result }
        else { summaryMessage = "要約を作成できませんでした。原文はそのまま保存されています" }
    }

}

// MARK: - 部品

// 黒いカプセルのボタン（ghost は薄いグレー）
struct CaptureButton: ButtonStyle {
    var ghost = false
    func makeBody(configuration: Configuration) -> some View {
        CaptureButtonBody(configuration: configuration, ghost: ghost)
    }
}

private struct CaptureButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let ghost: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.subheadline).bold()
            .padding(.vertical, 14)
            .foregroundStyle(ghost ? BooksStyle.ink : .white)
            .background(ghost ? BooksStyle.card : BooksStyle.ink, in: Capsule())
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.8 : 1)
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

// MARK: - AVCaptureSession ベースのカメラ（UIImagePickerController より起動が速い）

struct CameraPicker: View {
    var onImage: (UIImage?) -> Void

    @StateObject private var camera = CameraService()
    @State private var zoomBase: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreviewLayer(session: camera.session)
                .ignoresSafeArea()
                .gesture(
                    MagnifyGesture()
                        .onChanged { v in camera.setZoom(zoomBase * v.magnification) }
                        .onEnded { v in zoomBase = camera.zoom }
                )

            VStack {
                Spacer()

                if camera.zoom > 1.05 {
                    Text(String(format: "%.1fx", camera.zoom))
                        .font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(.bottom, 8)
                }

                HStack {
                    Button { onImage(nil) } label: {
                        Text("キャンセル")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(width: 80, height: 80)
                    }

                    Spacer()

                    Button {
                        camera.capture()
                    } label: {
                        ZStack {
                            Circle().fill(.white).frame(width: 70, height: 70)
                            Circle().stroke(.white.opacity(0.5), lineWidth: 4)
                                .frame(width: 80, height: 80)
                        }
                    }
                    .disabled(camera.capturing)

                    Spacer()

                    Color.clear.frame(width: 80, height: 80)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
        }
        .onAppear {
            camera.onCaptured = { img in onImage(img) }
            camera.start()
        }
        .onDisappear { camera.stop() }
    }
}

final class CameraService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private(set) var device: AVCaptureDevice?
    var onCaptured: ((UIImage) -> Void)?
    @Published var capturing = false
    @Published var zoom: CGFloat = 1
    private var configured = false

    func start() {
        guard !configured else {
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                if !session.isRunning { session.startRunning() }
            }
            return
        }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        device = dev
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            session.startRunning()
        }
    }

    func stop() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            session.stopRunning()
        }
    }

    func capture() {
        guard !capturing else { return }
        capturing = true
        let settings = AVCapturePhotoSettings()
        if let conn = output.connection(with: .video) {
            conn.videoRotationAngle = 90  // portrait
        }
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async { self.capturing = false }
            return
        }
        DispatchQueue.main.async { [self] in
            capturing = false
            onCaptured?(image)
        }
    }

    func setZoom(_ factor: CGFloat) {
        guard let device else { return }
        let clamped = min(max(factor, 1), min(device.activeFormat.videoMaxZoomFactor, 10))
        try? device.lockForConfiguration()
        device.videoZoomFactor = clamped
        device.unlockForConfiguration()
        DispatchQueue.main.async { self.zoom = clamped }
    }

    deinit { if session.isRunning { session.stopRunning() } }
}

private struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> CameraHostView {
        let v = CameraHostView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspect
        return v
    }
    func updateUIView(_ v: CameraHostView, context: Context) {}
}

private final class CameraHostView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

// 画面上のドラッグを元画像の正規化座標へ戻す。ズームと移動の両方を考慮する。
enum ReaderCoordinates {
    static func selection(start: CGPoint, end: CGPoint, size: CGSize,
                          scale: CGFloat, offset: CGSize) -> CGRect {
        func point(_ p: CGPoint) -> CGPoint {
            let x = ((p.x - size.width / 2 - offset.width) / max(scale, 1) + size.width / 2) / max(size.width, 1)
            let y = ((p.y - size.height / 2 - offset.height) / max(scale, 1) + size.height / 2) / max(size.height, 1)
            return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
        }
        let a = point(start), b = point(end)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
