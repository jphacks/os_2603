import SwiftUI
import UIKit
import CryptoKit

// 本番フロー: Secure Enclave + Face ID で DEK を守る。
// WrappedDEK（バックアップ）と暗号文は UserDefaults に永続化。
// シミュレータでは Keychain の biometryCurrentSet が使えないため
// エラーメッセージで案内する（クラッシュしない）。

struct ContentView: View {
    enum Phase { case setup, locked, unlocked, newDevice }

    // MARK: - UserDefaults キー

    private static let backupKey = "recall.wrappedDEK"
    private static let notesKey  = "recall.notes"

    // MARK: - State

    @State private var dek: SymmetricKey?
    @State private var phase: Phase = .setup
    @State private var recoveryKeyToShow: String?
    @State private var confirmedSaved = false

    @State private var notes: [Data] = []   // 暗号文のみ。平文はメモリに置かない。
    @State private var newNote = ""
    @State private var restoreInput = ""
    @State private var flash = ""
    @State private var flashOK = true
    @State private var busy = false

    // MARK: - 永続化ヘルパー

    private func loadBackup() -> WrappedDEK? {
        guard let data = UserDefaults.standard.data(forKey: Self.backupKey) else { return nil }
        return try? JSONDecoder().decode(WrappedDEK.self, from: data)
    }

    private func saveBackup(_ backup: WrappedDEK) {
        guard let data = try? JSONEncoder().encode(backup) else { return }
        UserDefaults.standard.set(data, forKey: Self.backupKey)
    }

    private func loadNotes() -> [Data] {
        (UserDefaults.standard.array(forKey: Self.notesKey) as? [Data]) ?? []
    }

    private func saveNotes(_ items: [Data]) {
        UserDefaults.standard.set(items, forKey: Self.notesKey)
    }

    // MARK: - body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusBar
                    switch phase {
                    case .setup:     setupCard
                    case .locked:    lockedCard
                    case .unlocked:  notesCard
                    case .newDevice: restoreCard
                    }
                    if phase == .unlocked || phase == .newDevice { scenarioCard }
                    backstageCard
                }
                .padding()
            }
            .navigationTitle("Recall 鍵フロー")
        }
        .onAppear(perform: onAppear)
    }

    // MARK: - 起動時

    private func onAppear() {
        notes = loadNotes()
        if loadBackup() == nil {
            doSetup()           // 初回: DEK 生成 → Keychain 保存 → リカバリーキー表示
        } else {
            phase = .locked     // 既存: ロック画面へ
        }
    }

    // MARK: - Setup

    // RecallVault.setup() は内部で DEKStore.save（biometryCurrentSet）を呼ぶため
    // メインスレッドをブロックしないよう Task.detached で実行する。
    private func doSetup() {
        phase = .setup
        busy = true
        Task {
            do {
                let (rk, backup) = try await Task.detached(priority: .userInitiated) {
                    try RecallVault.setup()
                }.value
                saveBackup(backup)
                recoveryKeyToShow = rk
                busy = false
            } catch let err as RecallCryptoError {
                busy = false; flashOK = false
                if case .keychainFailed(let status) = err {
                    flash = keychainMessage(status)
                }
            } catch {
                busy = false; flashOK = false
                flash = "セットアップ失敗: \(error)"
            }
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("リカバリーキーを発行").font(.headline)
            Text("一度だけ表示されます。必ず保管してください。アプリは保存しません。")
                .font(.caption).foregroundStyle(.secondary)

            if busy {
                ProgressView("Secure Enclave に鍵を生成中…").padding(.vertical, 4)
            } else if let rk = recoveryKeyToShow {
                Text(rk)
                    .font(.system(.title3, design: .monospaced)).bold()
                    .padding().frame(maxWidth: .infinity)
                    .background(.yellow.opacity(0.15)).cornerRadius(10)
                Button("コピー") { UIPasteboard.general.string = rk }
            }

            if !flash.isEmpty {
                Text(flash).font(.caption).foregroundStyle(flashOK ? .green : .red)
            }
            Toggle("保管しました", isOn: $confirmedSaved)
            Button("はじめる") {
                recoveryKeyToShow = nil     // アプリは忘れる。持つのは本人だけ。
                phase = .locked
            }
            .buttonStyle(.borderedProminent)
            .disabled(!confirmedSaved || recoveryKeyToShow == nil || busy)
        }
        .cardStyle()
    }

    // MARK: - Locked

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🔒 ロック中").font(.headline)
            Text("Secure Enclave に保管した DEK を Face ID で取り出します。")
                .font(.caption).foregroundStyle(.secondary)

            if busy {
                ProgressView("Face ID 認証中…").padding(.vertical, 4)
            } else {
                Button("Face ID で解錠") { unlock() }
                    .buttonStyle(.borderedProminent)
            }
            if !flash.isEmpty {
                Text(flash).font(.caption).foregroundStyle(flashOK ? .green : .red)
            }
        }
        .cardStyle()
    }

    // SecItemCopyMatching（biometric）はブロッキング呼び出しのため Task.detached で実行。
    private func unlock() {
        busy = true; flash = ""
        Task {
            do {
                let key = try await Task.detached(priority: .userInitiated) {
                    try RecallVault.unlock()
                }.value
                dek = key; phase = .unlocked; busy = false
            } catch let err as RecallCryptoError {
                busy = false; flashOK = false
                if case .keychainFailed(let status) = err {
                    flash = keychainMessage(status)
                }
            } catch {
                busy = false; flashOK = false
                flash = "解錠失敗: \(error)"
            }
        }
    }

    // MARK: - Notes（解錠中）

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ノート").font(.headline)
            HStack {
                TextField("メモを書く…", text: $newNote).textFieldStyle(.roundedBorder)
                Button("追加", action: addNote).buttonStyle(.bordered)
            }
            if notes.isEmpty {
                Text("まだノートがありません。").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(notes.enumerated()), id: \.offset) { _, data in
                    Text(decrypted(data))
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1)).cornerRadius(8)
                }
            }
            if !flash.isEmpty {
                Text(flash).font(.caption).foregroundStyle(flashOK ? .green : .red)
            }
            Button("ロック") { dek = nil; flash = ""; phase = .locked }
                .buttonStyle(.bordered)
        }
        .cardStyle()
    }

    private func addNote() {
        let t = newNote.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let key = dek, let ct = try? NoteCipher.encrypt(t, with: key) else { return }
        notes.append(ct)
        saveNotes(notes)    // 暗号文をディスクに永続化
        newNote = ""
    }

    private func decrypted(_ data: Data) -> String {
        guard let key = dek, let s = try? NoteCipher.decrypt(data, with: key) else { return "🔒" }
        return s
    }

    // MARK: - Scenario（機種変・紛失シミュレーション）

    private var scenarioCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("機種変・紛失をためす").font(.headline)
            Text("Keychain から DEK を消します。暗号文と WrappedDEK（バックアップ）は残ります。")
                .font(.caption).foregroundStyle(.secondary)
            Button("新しい端末にする（Keychain 消去）", role: .destructive) {
                DEKStore.wipe()         // Secure Enclave の鍵を消す（旧端末の喪失を再現）
                dek = nil; flash = ""; phase = .newDevice
            }
            .buttonStyle(.bordered)
        }
        .cardStyle()
    }

    // MARK: - Restore（リカバリーキーで復元）

    private var restoreCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("新しい端末").font(.headline)
            Text("Keychain に鍵はありません。リカバリーキーで DEK を復元し、再登録します。")
                .font(.caption).foregroundStyle(.secondary)
            TextField("リカバリーキーを入力…", text: $restoreInput)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
            if busy {
                ProgressView("復元中…").padding(.vertical, 4)
            } else {
                Button("復元する", action: restore).buttonStyle(.borderedProminent)
            }
            if !flash.isEmpty {
                Text(flash).font(.caption).foregroundStyle(flashOK ? .green : .red)
            }
        }
        .cardStyle()
    }

    private func restore() {
        guard let backup = loadBackup() else {
            flash = "バックアップが見つかりません"; flashOK = false; return
        }
        busy = true; flash = ""
        let input = restoreInput    // Task にキャプチャするためローカルにコピー
        Task {
            do {
                let key = try await Task.detached(priority: .userInitiated) {
                    // KeyWrap.unwrap が throw → restoreFailed（キー違い）
                    // DEKStore.save が throw  → keychainFailed（Keychain 書き込み失敗）
                    try RecallVault.restore(from: backup, recoveryKey: input)
                }.value
                dek = key; restoreInput = ""
                flashOK = true; flash = "復元成功。ノートが戻りました。"
                phase = .unlocked; busy = false
            } catch RecallCryptoError.restoreFailed {
                busy = false; flashOK = false
                flash = "✗ 復元失敗。リカバリーキーが違います（認証タグ不一致）。"
            } catch let err as RecallCryptoError {
                busy = false; flashOK = false
                if case .keychainFailed(let status) = err {
                    // 暗号復元は成功したが Keychain 保存で失敗（シミュレータ等）
                    flash = "暗号復元は成功しましたが Keychain 保存に失敗:\n\(keychainMessage(status))"
                }
            } catch {
                busy = false; flashOK = false
                flash = "復元失敗: \(error)"
            }
        }
    }

    // MARK: - Backstage

    private var backstageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("舞台裏").font(.headline)
            row("DEK", dek == nil ? "なし（ロック中）" : "メモリ上に在り")
            row("WrappedDEK",
                loadBackup() == nil ? "未保存" : "UserDefaults に永続化済み")
            row("ノート暗号文",
                notes.isEmpty ? "—" : "\(notes.count) 件（UserDefaults に永続化）")
            row("リカバリーキー", "アプリは保存しない")
        }
        .cardStyle()
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k)
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(v).font(.system(.caption, design: .monospaced))
            Spacer()
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            label(phase == .newDevice ? "新しい端末" : "この端末", ok: phase != .newDevice)
            label(dek == nil ? "鍵：なし" : "鍵：在り", ok: dek != nil)
        }
    }

    private func label(_ t: String, ok: Bool) -> some View {
        Text(t).font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
            .background((ok ? Color.green : Color.red).opacity(0.15))
            .foregroundStyle(ok ? .green : .red).clipShape(Capsule())
    }

    // MARK: - Keychain エラー文言

    private func keychainMessage(_ status: OSStatus) -> String {
        switch status {
        case errSecItemNotFound:
            return """
                Keychain に鍵が見つかりません。
                （シミュレータでは Secure Enclave が使えないため \
                biometryCurrentSet は動作しません。実機で試してください。）
                """
        case errSecUserCanceled:
            return "Face ID がキャンセルされました。"
        case errSecAuthFailed:
            return "Face ID 認証に失敗しました。"
        case errSecMissingEntitlement:
            return """
                Keychain エンタイトルメントが不足しています。
                （シミュレータでは .biometryCurrentSet は使えません。実機で試してください。）
                """
        case errSecParam:
            return """
                SecAccessControl の生成に失敗しました。
                （シミュレータでは Face ID 未設定の場合にこのエラーが出ます。）
                """
        default:
            #if targetEnvironment(simulator)
            return "Keychain エラー: \(status)（シミュレータでは Face ID / Secure Enclave は制限されています。実機で試してください。）"
            #else
            return "Keychain エラー: \(status)"
            #endif
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        self.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.2)))
            .cornerRadius(14)
    }
}

#Preview { ContentView() }
