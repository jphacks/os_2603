import SwiftUI

// Apple Books 風の見た目（白地・黒い文字・太い見出し・黒いカプセルのボタン・表紙を大きく）。
// 見た目の定義だけを置く。機能は持たない。

enum BooksStyle {
    static let background = Color.white
    static let card = Color(red: 0.961, green: 0.961, blue: 0.969)   // 薄いグレーのカード
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let subInk = Color(red: 0.52, green: 0.52, blue: 0.55)
    static let accent = Color(red: 0.0, green: 0.48, blue: 1.0)       // 文字ボタンの青

    /// 本の文字（付箋を貼った行・周りの文）用の明朝体
    static func serif(_ style: Font.TextStyle) -> Font {
        .system(style, design: .serif)
    }
}

/// 表紙の代わりに、書名から色を決めた仮の表紙を描く（本の画像は保存しないため）
struct BookCoverView: View {
    let book: Book
    var titleFont: Font = .system(size: 13, weight: .heavy)

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [color.opacity(0.8), color],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(titleFont)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(10)
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 4)
    }

    private var color: Color {
        let palette: [Color] = [
            Color(red: 0.85, green: 0.58, blue: 0.27),
            Color(red: 0.36, green: 0.58, blue: 0.84),
            Color(red: 0.35, green: 0.66, blue: 0.52),
            Color(red: 0.82, green: 0.42, blue: 0.38),
            Color(red: 0.52, green: 0.44, blue: 0.76),
        ]
        let index = abs(book.title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % palette.count
        return palette[index]
    }
}

/// 閉じるボタン（グレーの丸に ×）
struct BooksCloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BooksStyle.ink)
                .frame(width: 36, height: 36)
                .background(BooksStyle.card, in: Circle())
        }
        .accessibilityLabel("閉じる")
    }
}
