import Foundation

// 「開いてから付箋まで」を短くするための小さな記憶（UserDefaults）。
// 最後に開いた本と、本ごとの最後のページ番号を覚えておく。
enum AppStore {
    private static let lastBookKey = "bookmark.lastBookId"

    static var lastBookId: String? {
        get { UserDefaults.standard.string(forKey: lastBookKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastBookKey) }
    }

    static func lastPage(for bookId: UUID) -> Int? {
        let key = "bookmark.lastPage.\(bookId.uuidString)"
        let v = UserDefaults.standard.integer(forKey: key)
        return v > 0 ? v : nil
    }

    static func setLastPage(_ page: Int, for bookId: UUID) {
        let key = "bookmark.lastPage.\(bookId.uuidString)"
        UserDefaults.standard.set(page, forKey: key)
    }
}
