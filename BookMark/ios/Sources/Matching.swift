import Foundation

// 目印のあいまい一致（AIではなくアルゴリズム）。
// 再撮影でOCRが多少ずれても、付箋を元の行へ復元する。Web版からの移植。

func normalizeText(_ s: String) -> String {
    let noSpace = s.components(separatedBy: .whitespacesAndNewlines).joined()
    // 全角/半角などをならす（NFKC相当）＋小文字化
    return noSpace.precomposedStringWithCompatibilityMapping.lowercased()
}

private func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
    let m = a.count, n = b.count
    if m == 0 { return n }
    if n == 0 { return m }
    var prev = Array(0...n)
    var curr = Array(repeating: 0, count: n + 1)
    for i in 1...m {
        curr[0] = i
        for j in 1...n {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            curr[j] = Swift.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
        }
        swap(&prev, &curr)
    }
    return prev[n]
}

// 0〜1 の類似度（1が完全一致）。
func similarity(_ a: String, _ b: String) -> Double {
    let na = normalizeText(a)
    let nb = normalizeText(b)
    if na.isEmpty && nb.isEmpty { return 1 }
    let dist = levenshtein(Array(na), Array(nb))
    let maxLen = Swift.max(na.count, nb.count, 1)
    return 1 - Double(dist) / Double(maxLen)
}

// 目印 marker に最も近い行のインデックスを返す。しきい値未満は nil。
func findBestLine(marker: String, lines: [String], threshold: Double = 0.5) -> Int? {
    var best = -1
    var bestScore = -1.0
    for (i, line) in lines.enumerated() {
        if normalizeText(line).isEmpty { continue }
        let s = similarity(marker, line)
        if s > bestScore {
            bestScore = s
            best = i
        }
    }
    if best == -1 || bestScore < threshold { return nil }
    return best
}
