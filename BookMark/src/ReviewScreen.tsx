import { useMemo, useState } from "react";
import type { Sticky, StickyColor } from "./types";

const cvar = (c: StickyColor) => `var(--c-${c})`;

// 復習モード: 付箋の切り抜きを見て中身を思い出し、見出し・メモで答え合わせ。
// 本番ではAIが復習問題を作る。試作品では「周辺文 → 見出し/メモ」の暗記カード。
export function ReviewScreen({
  stickies,
  onClose,
}: {
  stickies: Sticky[];
  onClose: () => void;
}) {
  const deck = useMemo(() => {
    const arr = [...stickies];
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    return arr;
  }, [stickies]);

  const [i, setI] = useState(0);
  const [show, setShow] = useState(false);
  const card = deck[i];

  const next = () => {
    setShow(false);
    setI((x) => x + 1);
  };

  return (
    <div className="flip" style={{ background: "var(--paper)", color: "var(--ink)" }}>
      <div className="flip-top">
        <button
          className="close"
          style={{ background: "var(--ink)", color: "#fff" }}
          onClick={onClose}
        >
          閉じる
        </button>
        <span className="counter" style={{ color: "var(--ink-soft)" }}>
          {deck.length === 0 ? "" : `${Math.min(i + 1, deck.length)} / ${deck.length}`}
        </span>
      </div>

      <div className="content" style={{ paddingBottom: 24 }}>
        {deck.length === 0 ? (
          <div className="empty">
            <div className="big">📚</div>
            復習できる付箋がまだありません。
          </div>
        ) : i >= deck.length ? (
          <div className="empty">
            <div className="big">🎉</div>
            今回の復習は終わりです。おつかれさま！
            <div style={{ marginTop: 18 }}>
              <button
                className="btn-primary"
                style={{ maxWidth: 200, margin: "0 auto" }}
                onClick={() => {
                  setI(0);
                  setShow(false);
                }}
              >
                もう一度
              </button>
            </div>
          </div>
        ) : (
          <>
            <div
              className="quiz-card"
              style={{ ["--sticky-c" as any]: cvar(card.color) }}
            >
              <div className="q">p.{card.pageNumber} ・ ここ、何の話だった？</div>
              <div className="clip">
                {card.clipBefore.slice(-1).map((l, k) => (
                  <div key={"b" + k}>{l}</div>
                ))}
                <span className="marked">{card.marker}</span>
                {card.clipAfter.slice(0, 1).map((l, k) => (
                  <div key={"a" + k}>{l}</div>
                ))}
              </div>

              {show && (
                <div className="answer">
                  <p className="h">{card.heading}</p>
                  {card.memo ? (
                    <p className="m">{card.memo}</p>
                  ) : (
                    <p className="m" style={{ color: "var(--ink-soft)" }}>
                      （メモなし）
                    </p>
                  )}
                </div>
              )}

              <div className="reveal">
                {!show ? (
                  <button className="btn-primary" onClick={() => setShow(true)}>
                    答えを見る
                  </button>
                ) : (
                  <button className="btn-primary" onClick={next}>
                    次へ
                  </button>
                )}
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
