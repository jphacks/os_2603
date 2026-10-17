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
            RootTabView()
                .preferredColorScheme(.light)   // 明るい紙デザイン固定（ダークモードで文字が消えるのを防ぐ）
        }
        .modelContainer(container)
    }
}

/// 下のタブ：ホーム（撮る）／本（まとめ）／設定
struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Query private var books: [Book]
    @State private var appState = AppState()

    var body: some View {
        TabView(selection: $appState.tab) {
            HomeView()
                .tabItem { Label("ホーム", systemImage: "house.fill") }
                .tag(AppState.Tab.home)
            ShelfView()
                .tabItem { Label("ライブラリ", systemImage: "books.vertical") }
                .tag(AppState.Tab.books)
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(AppState.Tab.settings)
        }
        .tint(Theme.accent)
        .environment(appState)
        .onAppear(perform: seedIfEmpty)
    }

    private func seedIfEmpty() {
        guard books.isEmpty else { return }
        context.insert(Book(title: "オペレーティングシステム 第3版", author: "田中 ほか"))
        context.insert(Book(title: "アルゴリズムとデータ構造 入門", author: "佐藤"))
    }
}
