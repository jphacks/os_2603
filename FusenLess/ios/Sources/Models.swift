import SwiftUI
import SwiftData

enum StickyColor: String, CaseIterable, Codable {
    case yellow, pink, blue, green, purple

    var color: Color {
        switch self {
        case .yellow: return Color(red: 1.0, green: 0.878, blue: 0.4)
        case .pink:   return Color(red: 1.0, green: 0.62,  blue: 0.71)
        case .blue:   return Color(red: 0.557, green: 0.776, blue: 1.0)
        case .green:  return Color(red: 0.655, green: 0.89,  blue: 0.627)
        case .purple: return Color(red: 0.78,  green: 0.659, blue: 1.0)
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

@Model
final class Sticky {
    var id: UUID
    var pageNumber: Int
    var placed: Bool
    var marker: String
    var clipBefore: [String]
    var clipAfter: [String]
    var memo: String
    var heading: String
    // 表示用要約。復元に使う marker は原文のまま保持する。
    var summarizedText: String? = nil
    var colorRaw: String
    var importance: Int
    var order: Double
    var createdAt: Date
    // 暗号化されたメモ本文。平文の memo は編集後に空になる。
    var encryptedMemo: Data?
    // 覚えたフラグ（剥がして捨てた = mastered）。データは消さない。
    var mastered: Bool
    var masteredAt: Date?
    var reviewEnabled: Bool = false
    var reviewStyle: String? = nil
    var cropImageData: Data? = nil
    var nextReviewDate: Date? = nil
    var reviewInterval: Int = 1
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
        self.mastered = false
        self.masteredAt = nil
        self.reviewEnabled = false
        self.reviewStyle = nil
        self.cropImageData = nil
        self.nextReviewDate = nil
        self.reviewInterval = 1
        self.book = book
    }

    var color: StickyColor {
        get { StickyColor(rawValue: colorRaw) ?? .yellow }
        set { colorRaw = newValue.rawValue }
    }

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
