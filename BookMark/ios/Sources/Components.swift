import SwiftUI

/// カテゴリ名（設定で変えたものを反映する）
struct CategoryLabel: View {
    let color: StickyColor
    @AppStorage private var name: String

    init(color: StickyColor) {
        self.color = color
        _name = AppStorage(wrappedValue: color.defaultCategory, color.categoryKey)
    }

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color.color).frame(width: 10, height: 10)
            Text(name.isEmpty ? color.defaultCategory : name)
                .font(.subheadline)
                .foregroundStyle(color.ink)
        }
    }
}

/// 表紙。画像がなければ書名入りの仮の表紙を描く
struct BookCoverView: View {
    let book: Book

    var body: some View {
        Group {
            if let data = book.coverData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [placeholderColor.opacity(0.55), placeholderColor.opacity(0.9)],
                                   startPoint: .top, endPoint: .bottom)
                    Text(book.title)
                        .font(Theme.serif(.caption))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.ink.opacity(0.85))
                        .padding(8)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 4, x: 1, y: 3)
    }

    private var placeholderColor: Color {
        let palette = StickyColor.allCases
        let index = abs(book.title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % palette.count
        return palette[index].color
    }
}

/// 付箋カード：カテゴリ・ページ・日付・貼った行（マーカー）・メモ
struct NoteCard: View {
    let sticky: Sticky

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                CategoryLabel(color: sticky.color)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("p. \(sticky.pageNumber)").font(.subheadline)
                    Text(Theme.dateFormatter.string(from: sticky.createdAt)).font(.caption)
                }
                .foregroundStyle(Theme.subInk)
            }

            Text(markerText)
                .font(Theme.serif(.body))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            if sticky.memo.isEmpty {
                Text("タップしてメモを追加")
                    .font(.footnote)
                    .foregroundStyle(Theme.subInk.opacity(0.6))
            } else {
                Text(sticky.memo)
                    .font(Theme.serif(.subheadline))
                    .foregroundStyle(Theme.subInk)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    /// 行ごとに蛍光ペンを引いたように見せる
    private var markerText: AttributedString {
        var text = AttributedString("「\(sticky.marker)」")
        text.foregroundColor = Theme.ink
        text.backgroundColor = sticky.color.color.opacity(0.35)
        return text
    }
}

/// 本の側面。付箋の色タブがページの位置に並ぶ（B2: 側面から位置が分かる）
struct BookEdgeView: View {
    let stickies: [Sticky]
    let lastPage: Int
    var onTap: (Sticky) -> Void

    private let edgeWidth: CGFloat = 12
    private let tabWidth: CGFloat = 20
    private let tabHeight: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.height - tabHeight - 40, 1)
            ZStack(alignment: .topTrailing) {
                pageEdge
                    .frame(width: edgeWidth)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                ForEach(firstStickyPerPage, id: \.id) { sticky in
                    let fraction = CGFloat(sticky.pageNumber) / CGFloat(max(lastPage, 1))
                    UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4)
                        .fill(sticky.color.color)
                        .frame(width: tabWidth, height: tabHeight)
                        .shadow(color: .black.opacity(0.15), radius: 2, x: -1, y: 1)
                        .position(x: geo.size.width - tabWidth / 2 - edgeWidth + 6,
                                  y: 20 + tabHeight / 2 + min(fraction, 1) * usable)
                        .onTapGesture { onTap(sticky) }
                        .accessibilityLabel("p.\(sticky.pageNumber) の付箋へ")
                }
            }
        }
        .frame(width: edgeWidth + tabWidth)
    }

    private var firstStickyPerPage: [Sticky] {
        var seen = Set<Int>()
        return stickies.filter { seen.insert($0.pageNumber).inserted }
    }

    private var pageEdge: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.edge))
            var x: CGFloat = 1
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: 0.6, height: size.height)),
                             with: .color(.white.opacity(0.35)))
                x += 2.2
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 3, x: -2)
    }
}
