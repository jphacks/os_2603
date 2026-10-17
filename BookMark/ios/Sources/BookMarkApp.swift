import SwiftUI
import SwiftData

// 本の付箋アプリ（iPhoneネイティブ版）。
// Web試作で検証した体験・データ設計・あいまい一致アルゴリズムを移植し、
// OCRは端末内の Apple Vision（日本語）を使う。

@main
struct BookMarkApp: App {
    let container: ModelContainer

    init() {
        // 端末でのストア初期化が失敗しても起動を落とさない（黒画面＝クラッシュ対策）。
        do {
            container = try ModelContainer(for: Book.self, Sticky.self)
        } catch {
            print("ModelContainer failed, falling back to in-memory: \(error)")
            // 最低限メモリ内で起動する
            container = try! ModelContainer(
                for: Book.self, Sticky.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }

    var body: some Scene {
        WindowGroup {
            ShelfView()
                .background(Color(red: 0.969, green: 0.957, blue: 0.925))
                .preferredColorScheme(.light)   // 明るい紙デザイン固定（ダークモードで文字が消えるのを防ぐ）
        }
        .modelContainer(container)
    }
}
