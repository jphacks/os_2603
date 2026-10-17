import Foundation

// Apple の Foundation Models フレームワーク（端末内 LLM）を使う。
//
// 対応条件（公式ドキュメント / WWDC25 session "Meet Foundation Models framework"):
//   - iOS 26.0 以降
//   - Apple Intelligence 対応端末（A17 Pro / A18 / M シリーズ）
//   - Apple Intelligence が設定から有効化済み
//
// 非対応端末・iOS < 26・失敗時はすべて Sticky.makeHeading にフォールバック。
// クラッシュしない。外部通信しない。

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AIHelper {

    // MARK: - 可用性チェック

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    // MARK: - 見出し生成（15字以内・体言止め）

    /// 付箋の内容から一言見出しを生成する。失敗時は nil（呼び元が makeHeading にフォールバック）。
    static func generateHeading(
        marker: String,
        clipBefore: [String],
        clipAfter: [String],
        memo: String
    ) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }
        guard isAvailable else { return nil }

        let context = ([clipBefore.last, marker, clipAfter.first]
            .compactMap { $0 }).joined(separator: "→")
        let memoNote = memo.isEmpty ? "" : "\nメモ: \(memo)"
        let prompt = """
            本の付箋の内容から一言見出しを日本語で生成してください。
            制約: 15文字以内、体言止め、内容のある名詞のみ（「について」「の説明」不要）
            付箋: \(context)\(memoNote)
            見出しのみ出力。
            """
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let text = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(20)
            return text.isEmpty ? nil : String(text)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - 復習問題生成

    /// 付箋の内容から短い確認問題を 1 つ生成する。失敗時は nil。
    static func generateQuestion(
        marker: String,
        heading: String,
        memo: String,
        clipBefore: [String],
        clipAfter: [String]
    ) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }
        guard isAvailable else { return nil }

        let context = ([clipBefore.last, marker, clipAfter.first]
            .compactMap { $0 }).joined(separator: "→")
        let memoNote = memo.isEmpty ? "" : "\nメモ: \(memo)"
        let prompt = """
            以下の本の内容について、読者が理解しているか確認する問題を 1 つ日本語で作ってください。
            制約: 1 文、「何ですか？」「どういう意味ですか？」形式、答えが付箋内容から明確
            内容: \(context)
            見出し: \(heading)\(memoNote)
            問題文のみ出力。
            """
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let text = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - 付箋作成後に非同期で見出しを更新するヘルパー

    /// 付箋を保存した直後に呼ぶ。AI が使えれば heading を上書きする。
    static func improveHeading(for sticky: Sticky) {
        guard isAvailable else { return }
        Task.detached(priority: .utility) {
            guard let heading = await generateHeading(
                marker: sticky.marker,
                clipBefore: sticky.clipBefore,
                clipAfter: sticky.clipAfter,
                memo: sticky.memo
            ) else { return }
            await MainActor.run { sticky.heading = heading }
        }
    }
}
