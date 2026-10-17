import { useState } from "react";
import type { Sticky, StickyColor } from "./types";
import type { OcrLine } from "./ocr";

const cvar = (c: StickyColor) => `var(--c-${c})`;

// カメラで撮った写真の上に、OCRした行をタップ領域として重ね、
// 既存の付箋を対応行に自動配置して表示する。
export function PhotoReader({
  imageUrl,
  lines,
  pageNumber,
  onPageNumber,
  anchors,
  unplacedCount,
  placing,
  onStartPlacing,
  onCancelPlacing,
  onTapIndex,
  onRetake,
  onBackToSample,
}: {
  imageUrl: string;
  lines: OcrLine[];
  pageNumber: number | null;
  onPageNumber: (n: number | null) => void;
  anchors: Map<number, Sticky>;
  unplacedCount: number;
  placing: Sticky | null;
  onStartPlacing: () => void;
  onCancelPlacing: () => void;
  onTapIndex: (i: number) => void;
  onRetake: () => void;
  onBackToSample: () => void;
}) {
  const [nat, setNat] = useState<{ w: number; h: number } | null>(null);
  const [editingPage, setEditingPage] = useState(pageNumber == null);

  return (
    <>
      <div className="row" style={{ justifyContent: "space-between", marginBottom: 10, gap: 8 }}>
        {editingPage ? (
          <span className="page-chip" style={{ gap: 8 }}>
            ページ番号
            <input
              className="page-input"
              inputMode="numeric"
              defaultValue={pageNumber ?? ""}
              placeholder="例)12"
              onChange={(e) => {
                const v = e.target.value.replace(/[^0-9]/g, "");
                onPageNumber(v ? parseInt(v, 10) : null);
              }}
              onBlur={() => pageNumber != null && setEditingPage(false)}
            />
          </span>
        ) : (
          <span className="page-chip" onClick={() => setEditingPage(true)}>
            🔎 ページ {pageNumber} を認識 ✎
          </span>
        )}
        <div style={{ display: "flex", gap: 6 }}>
          <button className="iconbtn" onClick={onRetake}>
            📷 撮り直す
          </button>
          <button className="iconbtn" onClick={onBackToSample}>
            閉じる
          </button>
        </div>
      </div>

      {pageNumber == null ? (
        <div className="unplaced-banner" style={{ background: "#fdecea", borderColor: "#e0b4ab" }}>
          <span className="ub-ic">⚠️</span>
          <span className="ub-txt">
            ページ番号が読み取れませんでした。上の欄に入力してください。
          </span>
        </div>
      ) : placing ? (
        <div className="place-bar">
          <div className="pb-txt">
            <small>どの行の話？ 写真の行をタップで配置</small>
            <b>📝 {placing.heading}</b>
          </div>
          <button className="pb-cancel" onClick={onCancelPlacing}>
            やめる
          </button>
        </div>
      ) : (
        unplacedCount > 0 && (
          <button className="unplaced-banner" onClick={onStartPlacing}>
            <span className="ub-ic">📝</span>
            <span className="ub-txt">
              このページに位置未定のメモが <b>{unplacedCount}</b> 件
            </span>
            <span className="ub-go">配置する ›</span>
          </button>
        )
      )}

      <div className="photo-wrap">
        <img
          src={imageUrl}
          className="photo-img"
          onLoad={(e) =>
            setNat({
              w: e.currentTarget.naturalWidth,
              h: e.currentTarget.naturalHeight,
            })
          }
        />
        {nat && (
          <div className="photo-overlay">
            {lines.map((l, i) => {
              const st = anchors.get(i);
              return (
                <button
                  key={i}
                  className={"ocr-line" + (st ? " has-sticky" : "")}
                  style={{
                    left: `${(l.x0 / nat.w) * 100}%`,
                    top: `${(l.y0 / nat.h) * 100}%`,
                    width: `${((l.x1 - l.x0) / nat.w) * 100}%`,
                    height: `${((l.y1 - l.y0) / nat.h) * 100}%`,
                    ...(st ? { ["--sticky-c" as any]: cvar(st.color) } : {}),
                  }}
                  onClick={() => onTapIndex(i)}
                >
                  {st && <span className="otab">{"★".repeat(st.importance)}</span>}
                </button>
              );
            })}
          </div>
        )}
      </div>

      <p className="hint">
        {placing
          ? "メモを貼る行をタップしてください"
          : pageNumber == null
            ? "ページ番号を入れると付箋をつけられます"
            : "写真の行をタップで付箋。次に同じページを撮ると自動で戻ります"}
      </p>
    </>
  );
}
