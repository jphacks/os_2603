import { useRef, useState } from "react";
import type { Sticky, StickyColor } from "./types";

const cvar = (c: StickyColor) => `var(--c-${c})`;

// パラパラモード（B3）: 本が無くても、付箋のあるページを順にめくり、
// 周辺の文章で「この話だった」と思い出す。
export function FlipMode({
  stickies,
  bookTitle,
  startAt = 0,
  onClose,
}: {
  stickies: Sticky[];
  bookTitle: string;
  startAt?: number;
  onClose: () => void;
}) {
  const [index, setIndex] = useState(startAt);
  const trackRef = useRef<HTMLDivElement>(null);

  const onScroll = () => {
    const el = trackRef.current;
    if (!el) return;
    const i = Math.round(el.scrollLeft / el.clientWidth);
    if (i !== index) setIndex(i);
  };

  if (stickies.length === 0) {
    return (
      <div className="flip">
        <div className="flip-top">
          <button className="close" onClick={onClose}>
            閉じる
          </button>
          <span className="counter">{bookTitle}</span>
        </div>
        <div className="empty" style={{ color: "#c9c2b2" }}>
          <div className="big">🪶</div>
          まだ付箋がありません。
          <br />
          ページを撮って行をタップしてみましょう。
        </div>
      </div>
    );
  }

  return (
    <div className="flip">
      <div className="flip-top">
        <button className="close" onClick={onClose}>
          閉じる
        </button>
        <span className="counter">
          {index + 1} / {stickies.length} ・ {bookTitle}
        </span>
      </div>

      <div className="flip-track" ref={trackRef} onScroll={onScroll}>
        {stickies.map((s) => (
          <div
            key={s.id}
            className="flip-card"
            style={{ ["--sticky-c" as any]: cvar(s.color) }}
          >
            <div className="pn">p.{s.pageNumber}</div>
            <div className="cliplines">
              {s.clipBefore.map((l, i) => (
                <div key={"b" + i}>{l || "　"}</div>
              ))}
              <div className="marked">{s.marker}</div>
              {s.clipAfter.map((l, i) => (
                <div key={"a" + i}>{l || "　"}</div>
              ))}
            </div>
            <div className="fhead">
              <span className="dot" />
              {s.heading}
            </div>
            {s.memo && <div className="fmemo">{s.memo}</div>}
          </div>
        ))}
      </div>

      <div className="flip-dots">
        {stickies.map((s, i) => (
          <span key={s.id} className={"d" + (i === index ? " on" : "")} />
        ))}
      </div>
    </div>
  );
}
