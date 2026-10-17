// 撮影写真の前処理。OCR精度を上げるため、
// グレースケール化＋コントラスト強調＋適正サイズへの縮小を行う。
// （本番のiPhoneネイティブではApple Visionの高精度OCRを使う想定。
//  試作品のブラウザOCRでは前処理で底上げする。）

export interface Prepared {
  /** 画面表示用（元写真のまま）。 */
  displayUrl: string;
  /** OCRにかける前処理済みキャンバス。元画像と同じ縦横比なので
   *  OCRの座標(%)は表示画像にそのまま重ねられる。 */
  ocrCanvas: HTMLCanvasElement;
}

function loadImage(url: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = url;
  });
}

export async function prepareForOcr(file: File): Promise<Prepared> {
  const displayUrl = URL.createObjectURL(file);
  const img = await loadImage(displayUrl);

  // 長辺を 2000px 程度に。大きすぎると遅く、小さすぎると潰れる。
  const maxDim = 2000;
  const scale = Math.min(1, maxDim / Math.max(img.naturalWidth, img.naturalHeight));
  const w = Math.max(1, Math.round(img.naturalWidth * scale));
  const h = Math.max(1, Math.round(img.naturalHeight * scale));

  const canvas = document.createElement("canvas");
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext("2d")!;
  ctx.drawImage(img, 0, 0, w, h);

  const imgData = ctx.getImageData(0, 0, w, h);
  const d = imgData.data;

  // 1) グレースケール化＋輝度ヒストグラムの範囲を把握
  const lum = new Float32Array(w * h);
  let min = 255;
  let max = 0;
  for (let i = 0, p = 0; i < d.length; i += 4, p++) {
    const g = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
    lum[p] = g;
    if (g < min) min = g;
    if (g > max) max = g;
  }

  // 2) コントラスト・ストレッチ（min→0, max→255）＋軽いS字強調
  const range = Math.max(1, max - min);
  for (let i = 0, p = 0; i < d.length; i += 4, p++) {
    let v = ((lum[p] - min) / range) * 255;
    // 中間を締めて文字を濃く、紙を白く寄せる
    v = v < 128 ? v * 0.8 : 128 + (v - 128) * 1.25;
    v = Math.max(0, Math.min(255, v));
    d[i] = d[i + 1] = d[i + 2] = v;
  }
  ctx.putImageData(imgData, 0, 0);

  return { displayUrl, ocrCanvas: canvas };
}
