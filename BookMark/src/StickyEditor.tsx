import { useRef, useState } from "react";
import type { Importance, Sticky, StickyColor } from "./types";
import { deleteSticky, setColor, setImportance, setMemo } from "./store";
import { useSpeech } from "./useSpeech";

const COLORS: StickyColor[] = ["yellow", "pink", "blue", "green", "purple"];
const cvar = (c: StickyColor) => `var(--c-${c})`;

export function StickyEditor({
  sticky,
  onClose,
}: {
  sticky: Sticky;
  onClose: () => void;
}) {
  const [memo, setMemoLocal] = useState(sticky.memo);
  const baseRef = useRef(sticky.memo);
  const { listening, isSupported, start, stop } = useSpeech((text) => {
    const base = baseRef.current;
    setMemoLocal((base ? base + " " : "") + text);
  });

  const save = () => {
    setMemo(sticky.id, memo);
    onClose();
  };

  const toggleMic = () => {
    if (listening) {
      stop();
    } else {
      baseRef.current = memo;
      start();
    }
  };

  const remove = () => {
    if (confirm("この付箋を削除しますか？")) {
      deleteSticky(sticky.id);
      onClose();
    }
  };

  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <div
        className="sheet"
        style={{ ["--sticky-c" as any]: cvar(sticky.color) }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="grip" />
        {sticky.placed ? (
          <>
            <p className="marker">📍 {sticky.marker}</p>
            <div className="clipbox">
              {sticky.clipBefore.map((l, i) => (
                <div key={"b" + i}>{l}</div>
              ))}
              <div className="marked">{sticky.marker}</div>
              {sticky.clipAfter.map((l, i) => (
                <div key={"a" + i}>{l}</div>
              ))}
            </div>
          </>
        ) : (
          <>
            <p className="marker">
              📝 位置未定のメモ（p.{sticky.pageNumber}）
            </p>
            <div className="clipbox">
              本を撮って行をタップすると、このメモがその行に配置されます。
            </div>
          </>
        )}

        <p className="field-label">メモ</p>
        <textarea
          className="memo-input"
          placeholder="気づいたこと・覚えたいことをメモ"
          value={memo}
          onChange={(e) => setMemoLocal(e.target.value)}
        />
        <div className="row" style={{ marginTop: 10 }}>
          {isSupported ? (
            <button
              className={"mic" + (listening ? " rec" : "")}
              onClick={toggleMic}
            >
              {listening ? "● 録音中… 停止" : "🎤 声で入力"}
            </button>
          ) : (
            <span style={{ fontSize: 12, color: "var(--ink-soft)" }}>
              この端末では音声入力に非対応（手入力でOK）
            </span>
          )}
        </div>

        <div className="row spread">
          <span className="field-label" style={{ margin: 0 }}>
            色
          </span>
          <div className="swatches">
            {COLORS.map((c) => (
              <button
                key={c}
                className={"swatch" + (sticky.color === c ? " sel" : "")}
                style={{ background: cvar(c) }}
                onClick={() => setColor(sticky.id, c)}
                aria-label={c}
              />
            ))}
          </div>
        </div>

        <div className="row spread">
          <span className="field-label" style={{ margin: 0 }}>
            重要度
          </span>
          <div className="imp-pick">
            {([1, 2, 3] as Importance[]).map((n) => (
              <button
                key={n}
                className={sticky.importance === n ? "sel" : ""}
                onClick={() => setImportance(sticky.id, n)}
              >
                {"★".repeat(n)}
              </button>
            ))}
          </div>
        </div>

        <div className="sheet-actions">
          <button className="btn-danger" onClick={remove}>
            削除
          </button>
          <button className="btn-primary" onClick={save}>
            保存
          </button>
        </div>
      </div>
    </div>
  );
}
