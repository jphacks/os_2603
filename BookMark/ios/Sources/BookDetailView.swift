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

                Text("撮ったら、付箋を貼りたい部分を指でなぞって囲むだけ")
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
    @FocusState private var pageFieldFocused: Bool  // キーボード制御

    @State private var wholeLines: [OCRLine] = []
    @State private var wholeLoaded = false
    // anchors をキャッシュして毎フレームのレーベンシュタイン計算を回避
    @State private var cachedAnchors: [Int: Sticky] = [:]

    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    @State private var busy = false
    @State private var flash: CGRect?
    @State private var ocrPreview: (rect: CGRect, text: String)? // 選択領域に認識結果を表示
    @State private var message: String?

    // ズーム
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var isPinching = false

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        VStack(spacing: 10) {
            header
            GeometryReader { geo in
                let w = geo.size.width
                let h = w * image.size.height / max(image.size.width, 1)
                imageCanvas(w: w, h: h)
            }
            .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
            .padding(.horizontal, 16)

            // ヒントテキスト
            Group {
                if zoomScale > 1 {
                    Text("ダブルタップでズームリセット。ピンチアウトで拡大。")
                } else if pageNumber == nil {
                    Text("ページ番号を入れてから、貼りたい部分を囲んでください")
                } else if wholeLoaded {
                    Text("貼りたい部分を指でなぞって囲む（行タップでも可）")
                } else {
                    Text("貼りたい部分を指でなぞって囲むと付箋ができます")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)

            if let message {
                Text(message).font(.caption)
                    .foregroundStyle(Color(red: 0.75, green: 0.26, blue: 0.17))
            }
            Spacer(minLength: 0)
        }
        .toolbar {
            // numberPad には Done ボタンがないのでツールバーに追加
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") { pageFieldFocused = false }
            }
        }
        .onAppear {
            if let pn = pageNumber { pageText = String(pn) }
            haptic.prepare()
            if let pn = pageNumber,
               book.stickies.contains(where: { $0.placed && !$0.mastered && $0.pageNumber == pn }) {
                loadWholePage()
            }
        }
        .onChange(of: wholeLines.count) { _, _ in updateCachedAnchors() }
        .onChange(of: book.stickies.count) { _, _ in updateCachedAnchors() }
        .onChange(of: pageNumber) { _, _ in updateCachedAnchors() }
    }

    // MARK: - ヘッダー

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "number")
                Text("ページ")
                TextField("例)12", text: $pageText)
                    .frame(width: 56)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .focused($pageFieldFocused)
                    .onChange(of: pageText) { _, v in
                        pageNumber = Int(v.filter { $0.isNumber })
                        if let pn = pageNumber {
                            AppStore.setLastPage(pn, for: book.id)
                            if !wholeLoaded,
                               book.stickies.contains(where: { $0.placed && !$0.mastered && $0.pageNumber == pn }) {
                                loadWholePage()
                            }
                        }
                    }
            }
            .font(.footnote).bold()
            Spacer()
            if zoomScale > 1 {
                Button {
                    withAnimation(.spring()) {
                        zoomScale = 1; lastZoomScale = 1
                        panOffset = .zero; lastPanOffset = .zero
                    }
                } label: {
                    Label("リセット", systemImage: "arrow.down.left.and.arrow.up.right")
                        .font(.footnote)
                }
                .buttonStyle(.bordered).tint(.secondary)
            } else if !wholeLoaded {
                Button {
                    loadWholePage()
                } label: {
                    Label("全体を読む", systemImage: "text.viewfinder").font(.footnote)
                }
                .buttonStyle(.bordered).tint(.secondary)
            }
            Button("閉じる") { onClose() }.buttonStyle(.bordered)
        }
        .padding(.horizontal, 16).padding(.top, 12)
    }

    // MARK: - 画像キャンバス

    @ViewBuilder
    private func imageCanvas(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image(uiImage: image).resizable().frame(width: w, height: h)

            // OCR 行ハイライト（Canvas で一括描画 → ForEach より高速）
            if wholeLoaded {
                Canvas { ctx, size in
                    for (idx, line) in wholeLines.enumerated() {
                        let r = line.rect
                        let frame = CGRect(
                            x: r.minX * size.width,
                            y: r.minY * size.height,
                            width: r.width * size.width,
                            height: max(r.height * size.height, 14))
                        if let sticky = cachedAnchors[idx] {
                            ctx.fill(Path(frame),
                                     with: .color(Color(uiColor: UIColor(sticky.color.color).withAlphaComponent(0.32))))
                        }
                    }
                }
                .frame(width: w, height: h)
                .allowsHitTesting(false)

                // アンカー行のラベル（Canvas 外で描く）
                ForEach(Array(cachedAnchors.keys), id: \.self) { idx in
                    let line = wholeLines[idx]
                    let sticky = cachedAnchors[idx]!
                    let r = line.rect
                    Text(String(repeating: "★", count: sticky.importance))
                        .font(.system(size: 8)).bold()
                        .padding(.horizontal, 2)
                        .background(sticky.color.color)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .position(
                            x: (r.maxX) * w + 6,
                            y: (r.midY) * h)
                        .allowsHitTesting(false)
                }
            }

            // ドラッグ中の選択枠
            if let start = dragStart, let end = dragEnd {
                let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                  width: abs(end.x - start.x), height: abs(end.y - start.y))
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.1))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }

            // OCR 認識結果を選択範囲の近くに表示
            if let preview = ocrPreview {
                Text(String(preview.text.prefix(50)))
                    .font(.caption2)
                    .lineLimit(2)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.78))
                    .foregroundStyle(.white)
                    .cornerRadius(7)
                    .frame(maxWidth: w * 0.7, alignment: .leading)
                    .position(
                        x: max(w * 0.35, min(preview.rect.midX * w, w * 0.65)),
                        y: max(22, preview.rect.minY * h - 20))
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            // 付箋作成フラッシュ
            if let f = flash {
                Rectangle().fill(Color.yellow.opacity(0.4))
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
        // ズーム変換（描画のみ・ジェスチャ座標は変わらない）
        .scaleEffect(zoomScale, anchor: .center)
        .offset(panOffset)
        .animation(.interactiveSpring(response: 0.3), value: panOffset)
        .gesture(pinchGesture)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { v in
                    if isPinching { return }
                    if zoomScale > 1.05 {
                        panOffset = CGSize(
                            width: lastPanOffset.width + v.translation.width,
                            height: lastPanOffset.height + v.translation.height)
                    } else {
                        if dragStart == nil { dragStart = v.startLocation }
                        dragEnd = v.location
                    }
                }
                .onEnded { v in
                    if zoomScale > 1.05 {
                        lastPanOffset = panOffset
                    } else {
                        let start = dragStart ?? v.startLocation
                        finishDrag(start: start, end: v.location, w: w, h: h)
                        dragStart = nil; dragEnd = nil
                    }
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring()) {
                zoomScale = 1; lastZoomScale = 1
                panOffset = .zero; lastPanOffset = .zero
            }
        }
        .onTapGesture { location in
            guard zoomScale <= 1.05 else { return }
            let nx = location.x / w
            let ny = location.y / h
            if let idx = wholeLines.firstIndex(where: { l in
                let expanded = l.rect.insetBy(dx: -0.005, dy: -0.005)
                return expanded.contains(CGPoint(x: nx, y: ny))
            }) {
                tapLine(idx)
            }
        }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                isPinching = true
                zoomScale = max(1, min(5, lastZoomScale * value))
            }
            .onEnded { _ in
                lastZoomScale = zoomScale
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPinching = false
                }
            }
    }

    // MARK: - アンカーキャッシュ更新（負荷の高いレーベンシュタインを再描画ごとに走らせない）

    private func updateCachedAnchors() {
        guard wholeLoaded, let pn = pageNumber else { cachedAnchors = [:]; return }
        let texts = wholeLines.map { $0.text }
        var map: [Int: Sticky] = [:]
        for s in book.stickies where s.placed && !s.mastered && s.pageNumber == pn {
            if let i = findBestLine(marker: s.marker, lines: texts) { map[i] = s }
        }
        cachedAnchors = map
    }

    // MARK: - ドラッグ完了 → 範囲 OCR

    private func finishDrag(start: CGPoint, end: CGPoint, w: CGFloat, h: CGFloat) {
        let vx = min(start.x, end.x), vy = min(start.y, end.y)
        let vw = abs(end.x - start.x), vh = abs(end.y - start.y)
        guard vw > 12, vh > 8 else { return }
        guard let pn = pageNumber else { show("ページ番号を入れてください"); return }
        let rect = CGRect(x: vx/w, y: vy/h, width: vw/w, height: vh/h)

        busy = true; message = nil
        Task {
            let pad = max(0.03, Double(rect.height) * 0.9)
            let expanded = CGRect(
                x: max(0, rect.minX - 0.02),
                y: max(0, rect.minY - pad),
                width: min(1, rect.width + 0.04),
                height: min(1, rect.height + pad * 2))
            let lines = await OCR.recognize(image, regionOfInterest: expanded).lines

            func centerY(_ l: OCRLine) -> CGFloat { l.rect.midY }
            let sel    = lines.filter { centerY($0) >= rect.minY && centerY($0) <= rect.maxY }
            let before = lines.filter { centerY($0) < rect.minY }
            let after  = lines.filter { centerY($0) > rect.maxY }

            let markerLines = sel.isEmpty ? lines : sel
            let marker = markerLines.map { $0.text }.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            await MainActor.run {
                busy = false
                guard !marker.isEmpty else { show("文字が読み取れませんでした"); return }
                let clipBefore = before.suffix(2).map { $0.text }
                let clipAfter  = after.prefix(2).map { $0.text }
                createSticky(pageNumber: pn, marker: marker,
                             clipBefore: clipBefore, clipAfter: Array(clipAfter))
                // 選択範囲に認識テキストを一時表示
                withAnimation(.easeOut(duration: 0.15)) {
                    ocrPreview = (rect: rect, text: marker)
                }
                flashRect(rect)
                Task {
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    await MainActor.run {
                        withAnimation { ocrPreview = nil }
                    }
                }
            }
        }
    }

    // MARK: - 行タップ

    private func tapLine(_ i: Int) {
        if let s = cachedAnchors[i] { onEdit(s); return }
        guard let pn = pageNumber else { show("ページ番号を入れてください"); return }
        let texts = wholeLines.map { $0.text }
        if normalizeText(texts[i]).isEmpty { return }
        let before = Array(texts[max(0, i-2)..<i])
        let after  = Array(texts[(i+1)..<min(texts.count, i+3)])
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
        haptic.impactOccurred()
        AIHelper.improveHeading(for: sticky)  // AI が使えれば非同期で見出しを更新
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
                updateCachedAnchors()
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
