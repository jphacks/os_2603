import Foundation

// 本ごとの最後のページ番号などを覚えておく（UserDefaults）。
enum AppStore {
    static func lastPage(for bookId: UUID) -> Int? {
        let key = "bookmark.lastPage.\(bookId.uuidString)"
        let v = UserDefaults.standard.integer(forKey: key)
        return v > 0 ? v : nil
    }

    static func setLastPage(_ page: Int, for bookId: UUID) {
        let key = "bookmark.lastPage.\(bookId.uuidString)"
        UserDefaults.standard.set(page, forKey: key)
    }

    // MARK: - 色の名前（例：重要／疑問／テスト）

    static func defaultColorName(_ c: StickyColor) -> String {
        switch c {
        case .yellow: return "重要"
        case .pink:   return "疑問"
        case .blue:   return "あとで"
        case .green:  return "用語"
        case .purple: return "テスト"
        }
    }

    static func colorName(_ c: StickyColor) -> String {
        let key = "bookmark.colorName.\(c.rawValue)"
        if let n = UserDefaults.standard.string(forKey: key), !n.isEmpty { return n }
        return defaultColorName(c)
    }

    static func setColorName(_ name: String, for c: StickyColor) {
        let key = "bookmark.colorName.\(c.rawValue)"
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { UserDefaults.standard.removeObject(forKey: key) }
        else { UserDefaults.standard.set(trimmed, forKey: key) }
    }
}
