import SwiftUI

// RecallDemoApp は BookMarkApp に統合済み。@main は BookMarkApp.swift に一元化。
// このファイルは暗号デモの ContentView を BookMark 内から呼び出したい場合のために残す。
struct RecallDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
