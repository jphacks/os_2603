import SwiftUI
import SwiftData

// 付箋の色＝カテゴリ（A13/A17: 色の意味づけ）。カテゴリ名は設定で変えられる。
enum StickyColor: String, CaseIterable, Codable {
    case yellow, pink, blue, green, purple

    var color: Color {
        switch self {
        case .yellow: return Color(red: 0.949, green: 0.773, blue: 0.361)
        case .pink: return Color(red: 0.941, green: 0.565, blue: 0.478)
        case .blue: return Color(red: 0.498, green: 0.659, blue: 0.863)
        case .green: return Color(red: 0.549, green: 0.780, blue: 0.604)
        case .purple: return Color(red: 0.702, green: 0.616, blue: 0.859)
        }
    }

    /// 文字に使う少し濃い色
    var ink: Color {
        switch self {
        case .yellow: return Color(red: 0.78, green: 0.56, blue: 0.13)
        case .pink: return Color(red: 0.86, green: 0.42, blue: 0.33)
        case .blue: return Color(red: 0.33, green: 0.50, blue: 0.74)
        case .green: return Color(red: 0.33, green: 0.60, blue: 0.40)
        case .purple: return Color(red: 0.52, green: 0.42, blue: 0.72)
        }
    }

    var defaultCategory: String {
        switch self {
        case .yellow: return "大事"
        case .pink: return "疑問"
        case .blue: return "定義"
        case .green: return "具体例"
        case .purple: return "あとで調べる"
        }
    }

    var categoryKey: String { "category.\(rawValue)" }
}

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String?
    var isbn: String?
    var publisher: String?
    var publishedDate: String?
    var summary: String?
    var pageCount: Int?
    @Attribute(.externalStorage) var coverData: Data?
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

    /// 本に貼ってある付箋（ページ順）
    var placedStickies: [Sticky] {
        stickies.filter { $0.placed }
            .sorted { ($0.pageNumber, $0.order) < ($1.pageNumber, $1.order) }
    }

    func apply(_ info: BookInfo, cover: Data?) {
        title = info.title
        author = info.author ?? author
        publisher = info.publisher ?? publisher
        publishedDate = info.publishedDate ?? publishedDate
        summary = info.summary ?? summary
        pageCount = info.pageCount ?? pageCount
        if let cover { coverData = cover }
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
