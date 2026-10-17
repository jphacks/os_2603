import Foundation
import CryptoKit
import LocalAuthentication
import Security

// RecallCrypto — セキュリティ設計のコアを CryptoKit で実装したもの（課金不要）。
//
//   DEK（データ鍵）        … メモを暗号化する共通鍵（AES-256-GCM）。毎回使う
//   リカバリーキー         … 生成した高エントロピーのキー。1回だけ表示して保管してもらう
//   KEK                    … リカバリーキーから HKDF で導出。DEK を包むときだけ使う
//   Secure Enclave + Face ID … 日常の解錠。DEK へのアクセスを生体認証で守る（実機のみ）

enum RecallCryptoError: Error { case restoreFailed, keychainFailed(OSStatus) }

// MARK: - 1. メモの暗号化（ホットパス：毎回・一瞬）

enum NoteCipher {
    static func encrypt(_ text: String, with dek: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(Data(text.utf8), using: dek)
        return box.combined!            // nonce(12) + ciphertext + tag(16)
    }
    static func decrypt(_ data: Data, with dek: SymmetricKey) throws -> String {
        let box = try AES.GCM.SealedBox(combined: data)
        let pt  = try AES.GCM.open(box, using: dek)   // タグ不一致なら throw
        return String(decoding: pt, as: UTF8.self)
    }
}

// MARK: - 2. リカバリーキー（1回だけ表示して保管してもらう）

enum RecoveryKey {
    static func generate(groups: Int = 5) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var raw = [UInt8](repeating: 0, count: groups * 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, raw.count, &raw)
        let chars = raw.map { alphabet[Int($0) % alphabet.count] }
        return stride(from: 0, to: chars.count, by: 4)
            .map { String(chars[$0 ..< min($0 + 4, chars.count)]) }
            .joined(separator: "-")
    }
    static func normalize(_ key: String) -> Data {
        Data(key.uppercased().filter { $0.isLetter || $0.isNumber }.utf8)
    }
}

// MARK: - 3. DEK を包む / 解く（コールドパス：バックアップ・復元のときだけ）

struct WrappedDEK: Codable {        // バックアップに入る。鍵そのものは入らない。
    let salt: Data
    let ciphertext: Data            // KEK で暗号化した DEK（combined 形式）
}

enum KeyWrap {
    private static func deriveKEK(recoveryKey: String, salt: Data) -> SymmetricKey {
        let ikm = SymmetricKey(data: RecoveryKey.normalize(recoveryKey))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm, salt: salt,
            info: Data("recall-dek-wrap".utf8), outputByteCount: 32)
    }
    static func wrap(dek: SymmetricKey, recoveryKey: String) throws -> WrappedDEK {
        var salt = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
        let saltData = Data(salt)
        let kek = deriveKEK(recoveryKey: recoveryKey, salt: saltData)
        let rawDEK = dek.withUnsafeBytes { Data($0) }
        let box = try AES.GCM.seal(rawDEK, using: kek)
        return WrappedDEK(salt: saltData, ciphertext: box.combined!)
    }
    static func unwrap(_ wrapped: WrappedDEK, recoveryKey: String) throws -> SymmetricKey {
        let kek = deriveKEK(recoveryKey: recoveryKey, salt: wrapped.salt)
        do {
            let box = try AES.GCM.SealedBox(combined: wrapped.ciphertext)
            let rawDEK = try AES.GCM.open(box, using: kek)   // キーが違えば throw
            return SymmetricKey(data: rawDEK)
        } catch { throw RecallCryptoError.restoreFailed }
    }
}

// MARK: - 4. 日常の解錠（Secure Enclave + Face ID。実機でのみ完全に動く）

enum DEKStore {
    private static let account = "com.recall.dek"
    private static let service = "Recall"

    static func save(_ dek: SymmetricKey) throws {
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet, nil) else { throw RecallCryptoError.keychainFailed(errSecParam) }
        let raw = dek.withUnsafeBytes { Data($0) }
        SecItemDelete([kSecClass: kSecClassGenericPassword,
                       kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service, kSecAttrAccount: account,
            kSecValueData: raw, kSecAttrAccessControl: access,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw RecallCryptoError.keychainFailed(status) }
    }

    static func load(reason: String = "ノートを開きます") throws -> SymmetricKey {
        let ctx = LAContext()
        ctx.localizedReason = reason
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service, kSecAttrAccount: account,
            kSecReturnData: true, kSecUseAuthenticationContext: ctx,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else {
            throw RecallCryptoError.keychainFailed(status)
        }
        return SymmetricKey(data: data)
    }

    static func wipe() {
        SecItemDelete([kSecClass: kSecClassGenericPassword,
                       kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
    }
}

// MARK: - 5. 全体の流れ（実機向け：Keychain を使う）

enum RecallVault {
    static func setup() throws -> (recoveryKey: String, backup: WrappedDEK) {
        let dek = SymmetricKey(size: .bits256)
        let recoveryKey = RecoveryKey.generate()
        let backup = try KeyWrap.wrap(dek: dek, recoveryKey: recoveryKey)
        try DEKStore.save(dek)
        return (recoveryKey, backup)
    }
    static func unlock() throws -> SymmetricKey { try DEKStore.load() }
    static func restore(from backup: WrappedDEK, recoveryKey: String) throws -> SymmetricKey {
        let dek = try KeyWrap.unwrap(backup, recoveryKey: recoveryKey)
        try DEKStore.save(dek)
        return dek
    }
}
