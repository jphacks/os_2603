import SwiftUI

// RecallDemoApp は FusenLessApp に統合済み。@main は FusenLessApp.swift に一元化。
// このファイルは暗号デモの ContentView を FusenLess 内から呼び出したい場合のために残す。
struct RecallDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
