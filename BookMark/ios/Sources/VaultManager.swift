import Foundation
import CryptoKit
import Security

// VaultManager — DEK をアプリ起動時に自動ロード／生成するだけのシンプル版。
// Face ID・リカバリーキーは保留。Keychain に biometrics なしで保存する。

@Observable
final class VaultManager {
    private(set) var dek: SymmetricKey

    private static let service = "Recall"
    private static let account = "com.recall.dek.simple"

    init() {
        if let loaded = Self.loadDEK() {
            dek = loaded
        } else {
            let newDEK = SymmetricKey(size: .bits256)
            Self.saveDEK(newDEK)
            dek = newDEK
        }
    }

    // MARK: - 暗号化 / 復号

    func encrypt(_ text: String) -> Data? {
        let result = try? NoteCipher.encrypt(text, with: dek)
        if let result {
            print("[Vault] 暗号化: \(result.count) bytes ← \"\(text.prefix(20))\"")
        } else {
            print("[Vault] 暗号化失敗: \"\(text.prefix(20))\"")
        }
        return result
    }

    func decrypt(_ data: Data) -> String? {
        let result = try? NoteCipher.decrypt(data, with: dek)
        if let result {
            print("[Vault] 復号: \"\(result.prefix(20))\" ← \(data.count) bytes")
        } else {
            print("[Vault] 復号失敗: \(data.count) bytes")
        }
        return result
    }

    // MARK: - Keychain（biometrics なし）

    private static func loadDEK() -> SymmetricKey? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData:  true,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func saveDEK(_ dek: SymmetricKey) {
        let raw = dek.withUnsafeBytes { Data($0) }
        let delete: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(delete as CFDictionary)
        let add: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecValueData:        raw,
            kSecAttrAccessible:   kSecAttrAccessibleWhenUnlocked,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }
}
