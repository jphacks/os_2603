import SwiftUI
import SwiftData

// 付箋の色（A13/A17: 重要度・色の意味づけ）。
enum StickyColor: String, CaseIterable, Codable {
    case yellow, pink, blue, green, purple

    var color: Color {
        switch self {
        case .yellow: return Color(red: 1.0, green: 0.878, blue: 0.4)
        case .pink: return Color(red: 1.0, green: 0.62, blue: 0.71)
        case .blue: return Color(red: 0.557, green: 0.776, blue: 1.0)
        case .green: return Color(red: 0.655, green: 0.89, blue: 0.627)
        case .purple: return Color(red: 0.78, green: 0.659, blue: 1.0)
        }
    }

    static func cycle(_ index: Int) -> StickyColor {
        allCases[index % allCases.count]
    }
}

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String?
    var isbn: String?
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Sticky.book)
    var stickies: [Sticky]

    init(title: String, author: String? = nil, isbn: String? = nil) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.isbn = isbn
        self.createdAt = .now
        self.stickies = []
    }
}

// 付箋。画像は保存せず「本・ページ番号・目印・メモ・周辺の切り抜き」だけを持つ（設計の核）。
@Model
final class Sticky {
    var id: UUID
    var pageNumber: Int
    var placed: Bool          // A5: 位置未定(false)＝写真なしメモ
    var marker: String        // 目印（貼った行の文字）
    var clipBefore: [String]  // 周辺の切り抜き（B3: 本が無くても思い出す）
    var clipAfter: [String]
    var memo: String
    var heading: String       // 一言見出し（本番はAI、今は簡易生成）
    var colorRaw: String
    var importance: Int       // 1..3
    var order: Double
    var createdAt: Date
    var book: Book?

    init(pageNumber: Int, placed: Bool, marker: String,
         clipBefore: [String], clipAfter: [String],
         color: StickyColor, book: Book?) {
        self.id = UUID()
        self.pageNumber = pageNumber
        self.placed = placed
        self.marker = marker
        self.clipBefore = clipBefore
        self.clipAfter = clipAfter
        self.memo = ""
        self.heading = Sticky.makeHeading(memo: "", marker: marker)
        self.colorRaw = color.rawValue
        self.importance = 2
        self.order = Date().timeIntervalSince1970
        self.createdAt = .now
        self.book = book
    }

    var color: StickyColor {
        get { StickyColor(rawValue: colorRaw) ?? .yellow }
        set { colorRaw = newValue.rawValue }
    }

    // 付箋ごとの一言見出し（本番はAI、試作では簡易生成）。
    static func makeHeading(memo: String, marker: String) -> String {
        let base = (memo.isEmpty ? marker : memo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let noSpace = base.replacingOccurrences(
            of: "\\s+", with: "", options: .regularExpression)
        let trimmed = noSpace.drop { $0.isNumber || $0 == "." || $0 == "　" }
        let head = String(trimmed.prefix(14))
        return head.isEmpty ? "付箋" : head
    }
}
