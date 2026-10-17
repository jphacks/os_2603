// 目印の文字列のあいまい一致で、付箋を行に戻すアルゴリズム（AIではない）。
// 再撮影でOCR結果が多少ずれても、付箋を元の行へ復元するのが狙い。

/** 比較用に正規化: 空白除去・全角/半角・大文字小文字をならす。 */
export function normalize(s: string): string {
  return s
    .replace(/\s+/g, "")
    .normalize("NFKC")
    .toLowerCase();
}

/** レーベンシュタイン距離。 */
function levenshtein(a: string, b: string): number {
  const m = a.length;
  const n = b.length;
  if (m === 0) return n;
  if (n === 0) return m;
  let prev = Array.from({ length: n + 1 }, (_, i) => i);
  let curr = new Array(n + 1).fill(0);
  for (let i = 1; i <= m; i++) {
    curr[0] = i;
    for (let j = 1; j <= n; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
    }
    [prev, curr] = [curr, prev];
  }
  return prev[n];
}

/** 0〜1 の類似度。1 が完全一致。 */
export function similarity(a: string, b: string): number {
  const na = normalize(a);
  const nb = normalize(b);
  if (na === "" && nb === "") return 1;
  const dist = levenshtein(na, nb);
  const maxLen = Math.max(na.length, nb.length) || 1;
  return 1 - dist / maxLen;
}

export interface MatchResult {
  lineIndex: number;
  score: number;
}

/**
 * 目印 marker に最も近い行を、現在のページの行 lines から探す。
 * score がしきい値未満なら null（＝このページには無い）。
 */
export function findBestLine(
  marker: string,
  lines: string[],
  threshold = 0.5,
): MatchResult | null {
  let best: MatchResult = { lineIndex: -1, score: -1 };
  lines.forEach((line, i) => {
    if (normalize(line) === "") return;
    const score = similarity(marker, line);
    if (score > best.score) best = { lineIndex: i, score };
  });
  if (best.lineIndex === -1 || best.score < threshold) return null;
  return best;
}
