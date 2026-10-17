import SwiftUI
import SwiftData
import AVFoundation
import Photos

// 本の付箋アプリ（iPhoneネイティブ版）。
// Web試作で検証した体験・データ設計・あいまい一致アルゴリズムを移植し、
// OCRは端末内の Apple Vision（日本語）を使う。

@main
struct BookMarkApp: App {
    let container: ModelContainer
    let vault = VaultManager()

    init() {
        // 端末でのストア初期化が失敗しても起動を落とさない（黒画面＝クラッシュ対策）。
        do {
            container = try ModelContainer(for: Book.self, Sticky.self)
        } catch {
            print("ModelContainer failed, falling back to in-memory: \(error)")
            container = try! ModelContainer(
                for: Book.self, Sticky.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        NotificationScheduler.requestPermission()
        // カメラ・写真ライブラリ権限を事前にリクエストして初回起動時のラグを減らす
        AVCaptureDevice.requestAccess(for: .video) { _ in }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }
    }

    var body: some Scene {
        WindowGroup {
            ShelfView()
                .environment(vault)
                .background(BooksStyle.background)
                .preferredColorScheme(.light)
                .tint(BooksStyle.ink)
        }
        .modelContainer(container)
    }
}
