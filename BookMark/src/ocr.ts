import { createWorker, type Worker } from "tesseract.js";

// 端末内OCR（本番のiPhoneネイティブでは端末内OCRに相当）。
// ブラウザでは Tesseract.js を使い、写真から「行の文字＋位置」を取り出す。

export interface OcrLine {
  text: string;
  x0: number;
  y0: number;
  x1: number;
  y1: number;
}

export interface OcrResult {
  lines: OcrLine[];
  /** 読み取ったページ番号（見つからなければ null）。 */
  pageNumber: number | null;
}

let workerPromise: Promise<Worker> | null = null;
let progressCb: ((p: number, status: string) => void) | null = null;

// Tesseract の内部ステータスを日本語の見出しに変換。
function phaseLabel(status: string): string {
  if (status.includes("traineddata") || status.includes("loading language"))
    return "日本語辞書を読み込み中";
  if (status.includes("initiali")) return "エンジンを準備中";
  if (status.includes("recognizing")) return "文字を認識中";
  return "準備中";
}

function getWorker(): Promise<Worker> {
  if (!workerPromise) {
    // 日本語＋英数（O(n) などの数式・ページ番号のため eng も）。
    workerPromise = createWorker("jpn+eng", 1, {
      logger: (m: { status: string; progress: number }) => {
        if (progressCb) progressCb(m.progress ?? 0, phaseLabel(m.status));
      },
    });
  }
  return workerPromise;
}

/** 画像（File / canvas / img / dataURL）を OCR して行と位置を返す。 */
export async function recognizeImage(
  source: Parameters<Worker["recognize"]>[0],
  onProgress?: (p: number, status: string) => void,
): Promise<OcrResult> {
  progressCb = onProgress ?? null;
  try {
    const worker = await getWorker();
    const { data } = await worker.recognize(source, {}, { blocks: true });
    const lines = collectLines(data);
    return { lines, pageNumber: detectPageNumber(lines) };
  } finally {
    progressCb = null;
  }
}

function collectLines(data: any): OcrLine[] {
  const out: OcrLine[] = [];
  const push = (ln: any) => {
    const text = (ln.text || "").replace(/\s+/g, " ").trim();
    const bb = ln.bbox || {};
    if (text) {
      out.push({
        text,
        x0: bb.x0 ?? 0,
        y0: bb.y0 ?? 0,
        x1: bb.x1 ?? 0,
        y1: bb.y1 ?? 0,
      });
    }
  };
  if (Array.isArray(data.blocks)) {
    for (const b of data.blocks)
      for (const p of b.paragraphs || [])
        for (const l of p.lines || []) push(l);
  }
  if (out.length === 0 && Array.isArray(data.lines)) {
    data.lines.forEach(push);
  }
  // 読み順（上→下、同じ高さなら左→右）に並べる。
  out.sort((a, b) => a.y0 - b.y0 || a.x0 - b.x0);
  return out;
}

/** ページ番号を推定（数字だけの行で、上下の余白に近いものを優先）。 */
function detectPageNumber(lines: OcrLine[]): number | null {
  if (lines.length === 0) return null;
  const maxY = Math.max(...lines.map((l) => l.y1)) || 1;
  const cands = lines.filter((l) => /^\d{1,4}$/.test(l.text.replace(/\s/g, "")));
  if (cands.length === 0) return null;
  const score = (l: OcrLine) => {
    const top = l.y0 < 0.12 * maxY ? 1 : 0;
    const bottom = l.y1 > 0.88 * maxY ? 2 : 0;
    return top + bottom;
  };
  cands.sort((a, b) => score(b) - score(a));
  const n = parseInt(cands[0].text.replace(/\s/g, ""), 10);
  return Number.isFinite(n) ? n : null;
}
