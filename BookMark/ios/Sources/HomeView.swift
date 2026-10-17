import SwiftUI
import SwiftData
import PhotosUI
import UIKit

// ホーム：今日の付箋の目標（リング）→ 黒い「ページを撮る」→ 今週の記録 → 読んでいる本 → 最近の付箋。
// 撮ったら、貼りたい部分を囲んで付箋。

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]
    @Query private var allStickies: [Sticky]
    // AppStore.lastBookId と同じキー（最後に開いた本から始める）
    @AppStorage("bookmark.lastBookId") private var lastBookId = ""
    @AppStorage("dailyStickyGoal") private var dailyGoal = 3

    @State private var photo: UIImage?
    @State private var pageNumber: Int?
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var editing: Sticky?
    @State private var showAddBook = false

    private var book: Book? {
        books.first { $0.id.uuidString == lastBookId } ?? books.first
    }

    private var placedStickies: [Sticky] { allStickies.filter(\.placed) }

    var body: some View {
        NavigationStack {
            Group {
                if let photo, let book {
                    PhotoReaderView(
                        image: photo,
                        pageNumber: $pageNumber,
                        book: book,
                        onEdit: { editing = $0 },
                        onClose: { self.photo = nil })
                } else {
                    start
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("ホーム")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { StickyEditor(sticky: $0) }
            .sheet(isPresented: $showAddBook) {
                AddBookSheet { lastBookId = $0.id.uuidString }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in
                    showCamera = false          // 撮影/キャンセル後にカメラを閉じる
                    if let img { setPhoto(img) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, newItem in loadPicked(newItem) }
        }
    }

    private var start: some View {
        ScrollView {
            VStack(spacing: 28) {
                if let book {
                    goalSection(book)
                    weekSection
                    Divider()
                    readingBooks(book)
                    recentNotes(book)
                } else {
                    ContentUnavailableView {
                        Label("本がまだありません", systemImage: "books.vertical")
                    } description: {
                        Text("裏表紙のISBNバーコードをかざして、読んでいる本を登録しましょう")
                    } actions: {
                        Button("本を登録する") { showAddBook = true }
                            .buttonStyle(CaptureButton())
                    }
                    .padding(.top, 60)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
    }

    // MARK: - 今日の付箋（読書目標のリング）

    private var todayCount: Int {
        placedStickies.filter { Calendar.current.isDateInToday($0.createdAt) }.count
    }

    private func goalSection(_ book: Book) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("付箋の目標").font(.title2.bold()).foregroundStyle(Theme.ink)
                Text("毎日少しずつ付箋を貼って、学んだことを本の外に残しましょう。")
                    .font(.footnote)
                    .foregroundStyle(Theme.subInk)
                    .multilineTextAlignment(.center)
            }

            GoalRing(progress: Double(todayCount) / Double(max(dailyGoal, 1))) {
                VStack(spacing: 2) {
                    Text("今日の付箋").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text("\(todayCount)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                    Text("（目標 \(dailyGoal) 枚）").font(.footnote).foregroundStyle(Theme.subInk)
                }
            }
            .frame(width: 250, height: 210)

            Button { showCamera = true } label: {
                VStack(spacing: 2) {
                    Text("ページを撮る").font(.headline)
                    Text(book.title).font(.caption).opacity(0.75).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CaptureButton())
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

            HStack(spacing: 18) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("写真を選ぶ", systemImage: "photo")
                }
                Button { setPhoto(Sample.render(Sample.pages[0])) } label: {
                    Label("サンプルで試す", systemImage: "wand.and.stars")
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.ink)
        }
    }

    // MARK: - 今週の記録（曜日の丸）

    private var weekSection: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)        // 1 = 日曜
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0 - (weekday - 1), to: today) }
        let symbols = ["日", "月", "火", "水", "木", "金", "土"]
        let activeDays = Set(placedStickies.map { calendar.startOfDay(for: $0.createdAt) })

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    let done = activeDays.contains(day)
                    let isToday = day == today
                    Text(symbols[i])
                        .font(.caption.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(done ? .white : (day > today ? Theme.subInk.opacity(0.5) : Theme.ink))
                        .background(Circle().fill(done ? Theme.ring : .clear))
                        .overlay(Circle().stroke(isToday && !done ? Theme.ring : Theme.separator,
                                                 lineWidth: isToday ? 2 : 1))
                }
            }
            VStack(spacing: 2) {
                Text(streak > 0 ? "\(streak) 日連続で付箋を貼っています" : "今日から連続記録を始めましょう")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
                Text("これまでの付箋 \(placedStickies.count) 枚").font(.caption).foregroundStyle(Theme.subInk)
            }
        }
    }

    /// 今日（まだなら昨日）までさかのぼって、付箋を貼った日が何日続いているか
    private var streak: Int {
        let calendar = Calendar.current
        let days = Set(placedStickies.map { calendar.startOfDay(for: $0.createdAt) })
        var day = calendar.startOfDay(for: .now)
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    // MARK: - 読んでいる本（表紙の横並び。タップで切り替え）

    private func readingBooks(_ current: Book) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "読んでいる本", subtitle: "表紙をタップすると、撮る本を切り替えます")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 16) {
                    ForEach(books) { b in
                        Button { withAnimation { lastBookId = b.id.uuidString } } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                BookCoverView(book: b)
                                    .frame(width: 92, height: 136)
                                    .overlay(alignment: .bottomTrailing) {
                                        if b.id == current.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(.white, Theme.ring)
                                                .padding(5)
                                        }
                                    }
                                Text(b.title)
                                    .font(.caption)
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                    .frame(width: 92, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button { showAddBook = true } label: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.card)
                            .frame(width: 92, height: 136)
                            .overlay(Image(systemName: "plus").font(.title2).foregroundStyle(Theme.subInk))
                            .padding(.bottom, 22)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private func recentNotes(_ book: Book) -> some View {
        let recent = book.stickies.filter(\.placed).sorted { $0.createdAt > $1.createdAt }.prefix(3)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "最近の付箋")
                ForEach(Array(recent)) { s in
                    Button { editing = s } label: { NoteCard(sticky: s) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    // 撮影/選択した画像を開く。ページ番号は前回の値を初期値に（開いてから付箋までを短く）。
    // カメラ写真は回転情報を持つため、正立に焼き込んでから使う（囲んだ範囲=OCR範囲のズレ防止）。
    private func setPhoto(_ image: UIImage) {
        guard let book else { return }
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

/// 下が開いた円弧のリング（Apple Books の読書目標のような見た目）
struct GoalRing<Content: View>: View {
    let progress: Double
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Theme.card, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * min(max(progress, 0), 1))
                .stroke(Theme.ring, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeOut(duration: 0.6), value: progress)
            content.offset(y: 8)
        }
        .padding(5)
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

    @AppStorage("lastStickyColor") private var lastColor = StickyColor.yellow.rawValue
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
                        .overlay(Rectangle().stroke(Theme.separator))

                    if wholeLoaded {
                        ForEach(Array(wholeLines.enumerated()), id: \.element.id) { idx, line in
                            let r = line.rect
                            let st = anchors[idx]
                            Rectangle()
                                .fill((st?.color.color ?? .clear).opacity(st == nil ? 0.001 : 0.4))
                                .overlay(alignment: .trailing) {
                                    if let s = st {
                                        // ページの端から飛び出した付箋のタブ
                                        UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3)
                                            .fill(s.color.color)
                                            .frame(width: 10)
                                            .offset(x: 10)
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
                            .strokeBorder(Theme.accent, lineWidth: 2)
                            .background(Theme.accent.opacity(0.12))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                    }

                    if let f = flash {
                        Rectangle().fill((StickyColor(rawValue: lastColor) ?? .yellow).color.opacity(0.45))
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
                 : wholeLoaded ? "貼りたい部分を指でなぞって囲む（行タップでも可）"
                               : "貼りたい部分を指でなぞって囲むと付箋ができます")
                .font(.caption).foregroundStyle(Theme.subInk)
                .frame(maxWidth: .infinity)
            if let message {
                Text(message).font(.caption).foregroundStyle(StickyColor.pink.ink)
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
                Text("ページ").fixedSize()
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
        // 色＝カテゴリ。前回選んだカテゴリで貼る
        let sticky = Sticky(
            pageNumber: pn, placed: true, marker: marker,
            clipBefore: clipBefore, clipAfter: clipAfter,
            color: StickyColor(rawValue: lastColor) ?? .yellow, book: book)
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

// 回転情報を画素に焼き込み、orientation を .up にそろえた画像を返す。
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
