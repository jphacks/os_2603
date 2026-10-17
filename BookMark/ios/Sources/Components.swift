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
                .font(.subheadline.weight(.semibold))
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
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [book.placeholderColor.opacity(0.75), book.placeholderColor],
                                   startPoint: .top, endPoint: .bottom)
                    Text(book.title)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(10)
                        .minimumScaleFactor(0.5)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.06)))
        .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 4)
    }
}

extension Book {
    /// 表紙がない本の仮の色（書名から決まる）
    var placeholderColor: Color { Color(uiColor: placeholderUIColor) }

    var placeholderUIColor: UIColor {
        let palette: [UIColor] = [
            UIColor(red: 0.85, green: 0.62, blue: 0.30, alpha: 1),
            UIColor(red: 0.42, green: 0.62, blue: 0.86, alpha: 1),
            UIColor(red: 0.40, green: 0.70, blue: 0.55, alpha: 1),
            UIColor(red: 0.84, green: 0.45, blue: 0.40, alpha: 1),
            UIColor(red: 0.55, green: 0.47, blue: 0.78, alpha: 1),
        ]
        let index = abs(title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % palette.count
        return palette[index]
    }

    /// 本の画面の上の背景色（表紙の平均色を暗めに）
    var heroColor: Color {
        Color(uiColor: (CoverColor.average(of: coverData) ?? placeholderUIColor).darkened(0.45))
    }
}

/// 付箋カード：カテゴリ・ページ・日付・貼った行（マーカー）・メモ
struct NoteCard: View {
    let sticky: Sticky

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                CategoryLabel(color: sticky.color)
                Spacer()
                Text("p.\(sticky.pageNumber) ・ \(Theme.dateFormatter.string(from: sticky.createdAt))")
                    .font(.caption)
                    .foregroundStyle(Theme.subInk)
            }

            Text(markerText)
                .font(Theme.serif(.body))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            if sticky.memo.isEmpty {
                Text("タップしてメモを追加")
                    .font(.footnote)
                    .foregroundStyle(Theme.subInk.opacity(0.7))
            } else {
                Text(sticky.memo)
                    .font(.subheadline)
                    .foregroundStyle(Theme.subInk)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    /// 行に蛍光ペンを引いたように見せる
    private var markerText: AttributedString {
        var text = AttributedString(sticky.marker)
        text.foregroundColor = Theme.ink
        text.backgroundColor = sticky.color.color.opacity(0.35)
        return text
    }
}

/// 本の側面（横向き）。付箋の色タブがページの位置に並ぶ（B2: 側面から位置が分かる）
struct BookEdgeView: View {
    let stickies: [Sticky]
    let lastPage: Int
    var onTap: (Sticky) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    pageEdge.frame(height: 14).offset(y: 9)
                    ForEach(firstStickyPerPage, id: \.id) { sticky in
                        let fraction = min(CGFloat(sticky.pageNumber) / CGFloat(max(lastPage, 1)), 1)
                        UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                            .fill(sticky.color.color)
                            .frame(width: 14, height: 18)
                            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                            .position(x: 7 + fraction * (geo.size.width - 14), y: 6)
                            .onTapGesture { onTap(sticky) }
                            .accessibilityLabel("p.\(sticky.pageNumber) の付箋へ")
                    }
                }
            }
            .frame(height: 24)
            HStack {
                Text("p.1")
                Spacer()
                Text("p.\(lastPage)")
            }
            .font(.caption2)
            .foregroundStyle(Theme.subInk)
        }
    }

    private var firstStickyPerPage: [Sticky] {
        var seen = Set<Int>()
        return stickies.filter { seen.insert($0.pageNumber).inserted }
    }

    private var pageEdge: some View {
        Canvas { context, size in
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2),
                         with: .color(Theme.edge))
            var y: CGFloat = 1.5
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.6)),
                             with: .color(.white.opacity(0.5)))
                y += 2.2
            }
        }
    }
}
