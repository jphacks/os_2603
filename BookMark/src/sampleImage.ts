import type { SamplePage } from "./types";

// サンプルページの本文を「本の写真」に見立てた画像に描く。
// カメラが無い環境でも、OCR → あいまい一致 → 自動配置 の一連を確かめるため。
export function renderPageToCanvas(page: SamplePage): HTMLCanvasElement {
  const W = 1000;
  const margin = 70;
  const lh = 58;
  const top = 90;
  const bottom = 120;
  const H = top + page.lines.length * lh + bottom;

  const canvas = document.createElement("canvas");
  canvas.width = W;
  canvas.height = H;
  const ctx = canvas.getContext("2d")!;

  ctx.fillStyle = "#ffffff";
  ctx.fillRect(0, 0, W, H);

  ctx.fillStyle = "#111111";
  ctx.textBaseline = "top";
  ctx.font =
    "34px -apple-system, 'Hiragino Sans', 'Yu Gothic', 'Noto Sans JP', sans-serif";

  page.lines.forEach((line, i) => {
    if (line) ctx.fillText(line, margin, top + i * lh);
  });

  // ページ番号（下中央）。
  ctx.font = "30px -apple-system, sans-serif";
  ctx.textAlign = "center";
  ctx.fillText(String(page.pageNumber), W / 2, H - bottom + 30);

  return canvas;
}
