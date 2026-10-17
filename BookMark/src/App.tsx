import { useMemo, useRef, useState, type ChangeEvent } from "react";
import type { Book, Sticky, StickyColor } from "./types";
import {
  addBook,
  addQuickMemo,
  addSticky,
  getLastBookId,
  getSamplePages,
  moveSticky,
  placeSticky,
  setLastBookId,
  stickiesForBook,
  useStore,
} from "./store";
import { findBestLine, normalize } from "./matching";
import { StickyEditor } from "./StickyEditor";
import { useSpeech } from "./useSpeech";
import { PhotoReader } from "./PhotoReader";
import { recognizeImage, type OcrLine } from "./ocr";
import { renderPageToCanvas } from "./sampleImage";
import { prepareForOcr } from "./preprocess";
import { FlipMode } from "./FlipMode";
import { ReviewScreen } from "./ReviewScreen";

const cvar = (c: StickyColor) => `var(--c-${c})`;

type View = { name: "shelf" } | { name: "book"; bookId: string };
type Tab = "read" | "list";
type Overlay = null | "flip" | "review";

function clipAround(lines: string[], i: number) {
  return {
    before: lines.slice(Math.max(0, i - 2), i),
    after: lines.slice(i + 1, i + 3),
  };
}

// 再撮影のOCRズレを再現（1文字ノイズ＋先頭オフセット）。
// 目印のあいまい一致で付箋が元の行に戻ることを確かめるためのデモ用。
function perturb(lines: string[]): string[] {
  const out = lines.map((l) => {
    if (l.length > 6 && Math.random() < 0.3) {
      const pos = Math.floor(Math.random() * l.length);
      return l.slice(0, pos) + "の" + l.slice(pos + 1);
    }
    return l;
  });
  return ["", ...out];
}

export default function App() {
  const { books, stickies } = useStore();
  const [view, setView] = useState<View>({ name: "shelf" });
  const [editingId, setEditingId] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [addOpen, setAddOpen] = useState(false);
  const [quickMemoBookId, setQuickMemoBookId] = useState<string | null>(null);

  const showToast = (m: string) => {
    setToast(m);
    window.setTimeout(() => setToast((t) => (t === m ? null : t)), 1600);
  };

  const openBook = (bookId: string) => {
    setLastBookId(bookId);
    setView({ name: "book", bookId });
  };

  const editing = editingId
    ? stickies.find((s) => s.id === editingId) ?? null
    : null;
  const quickMemoBook = quickMemoBookId
    ? books.find((b) => b.id === quickMemoBookId) ?? null
    : null;

  return (
    <div className="app">
      {view.name === "shelf" ? (
        <Shelf
          books={books}
          stickies={stickies}
          onOpen={(b) => openBook(b.id)}
          onAdd={() => setAddOpen(true)}
          onQuickMemo={(bookId) => setQuickMemoBookId(bookId)}
          onEditSticky={(s) => {
            openBook(s.bookId);
            setEditingId(s.id);
          }}
        />
      ) : (
        <BookScreen
          key={view.bookId}
          bookId={view.bookId}
          books={books}
          stickies={stickies}
          onBack={() => setView({ name: "shelf" })}
          onEdit={(id) => setEditingId(id)}
          onQuickMemo={() => setQuickMemoBookId(view.bookId)}
          toast={showToast}
        />
      )}

      {editing && (
        <StickyEditor sticky={editing} onClose={() => setEditingId(null)} />
      )}
      {addOpen && (
        <AddBookModal
          onClose={() => setAddOpen(false)}
          onCreate={(b) => {
            setAddOpen(false);
            openBook(b.id);
          }}
        />
      )}
      {quickMemoBook && (
        <QuickMemoSheet
          book={quickMemoBook}
          onClose={() => setQuickMemoBookId(null)}
          toast={showToast}
        />
      )}
      {toast && <div className="toast">{toast}</div>}
    </div>
  );
}

// ---------------- 本棚 ----------------
function Shelf({
  books,
  stickies,
  onOpen,
  onAdd,
  onQuickMemo,
  onEditSticky,
}: {
  books: Book[];
  stickies: Sticky[];
  onOpen: (b: Book) => void;
  onAdd: () => void;
  onQuickMemo: (bookId: string) => void;
  onEditSticky: (s: Sticky) => void;
}) {
  const [q, setQ] = useState("");
  const nq = normalize(q);

  // A5: 最後に開いた本にワンタップでメモ（毎回選ばせない）。
  const lastBookId = getLastBookId();
  const lastBook = books.find((b) => b.id === lastBookId);

  // A16: 本をまたいで付箋を探す
  const results =
    nq.length === 0
      ? []
      : stickies.filter(
          (s) =>
            normalize(s.marker).includes(nq) ||
            normalize(s.memo).includes(nq) ||
            normalize(s.heading).includes(nq),
        );

  const titleOf = (id: string) =>
    books.find((b) => b.id === id)?.title ?? "本";

  return (
    <>
      <div className="topbar">
        <h1>📖 BookMark</h1>
        <button className="iconbtn" onClick={onAdd}>
          ＋ 本を追加
        </button>
      </div>
      <div className="content">
        {lastBook && (
          <button className="quickmemo-shortcut" onClick={() => onQuickMemo(lastBook.id)}>
            <span className="qm-ic">✍️</span>
            <span className="qm-txt">
              <b>「{lastBook.title}」にすぐメモ</b>
              <small>写真なしでOK（電車の中でも）</small>
            </span>
            <span className="qm-go">›</span>
          </button>
        )}
        <input
          className="search"
          style={{
            width: "100%",
            border: "1px solid var(--line)",
            borderRadius: 12,
            padding: "11px 13px",
            fontSize: 15,
            background: "var(--paper-2)",
            marginBottom: 6,
          }}
          placeholder="🔍 付箋を本をまたいで探す"
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />

        {nq.length > 0 ? (
          <>
            <div className="section-label">
              検索結果 {results.length} 件
            </div>
            {results.length === 0 ? (
              <div className="empty">一致する付箋がありません。</div>
            ) : (
              results.map((s) => (
                <StickyRow
                  key={s.id}
                  s={s}
                  bookTitle={titleOf(s.bookId)}
                  onClick={() => onEditSticky(s)}
                />
              ))
            )}
          </>
        ) : (
          <>
            <div className="section-label">本棚</div>
            <div className="shelf-grid">
              {books.map((b) => {
                const count = stickies.filter(
                  (s) => s.bookId === b.id,
                ).length;
                return (
                  <button
                    key={b.id}
                    className="book-card"
                    onClick={() => onOpen(b)}
                  >
                    <span className="spine" />
                    <h3>{b.title}</h3>
                    <span className="meta">{b.author ?? "著者不明"}</span>
                    <span className="count">付箋 {count}</span>
                  </button>
                );
              })}
              <button className="add-book" onClick={onAdd}>
                ＋ 本を追加
              </button>
            </div>
          </>
        )}
      </div>
    </>
  );
}

function StickyRow({
  s,
  bookTitle,
  unplaced,
  onClick,
  onMove,
}: {
  s: Sticky;
  bookTitle?: string;
  unplaced?: boolean;
  onClick: () => void;
  onMove?: (dir: -1 | 1) => void;
}) {
  return (
    <div className="sticky-row" style={{ ["--sticky-c" as any]: cvar(s.color) }}>
      <span className="bar" />
      <button
        className="body"
        style={{ background: "transparent", border: 0, padding: 0, textAlign: "left" }}
        onClick={onClick}
      >
        <p className="head">
          {s.heading}
          <span className="pagetag">p.{s.pageNumber}</span>
          {unplaced ? (
            <span className="badge-unplaced">位置未定</span>
          ) : (
            <span className="imp">{"★".repeat(s.importance)}</span>
          )}
        </p>
        {unplaced ? (
          <div className="memo">📝 {s.memo || "（メモ空）"}</div>
        ) : (
          <>
            <div className="clip">{s.marker}</div>
            {s.memo && <div className="memo">📝 {s.memo}</div>}
          </>
        )}
        {bookTitle && (
          <div className="clip" style={{ marginTop: 4 }}>
            📘 {bookTitle}
          </div>
        )}
      </button>
      {onMove && (
        <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
          <button className="iconbtn" style={{ padding: "4px 8px" }} onClick={() => onMove(-1)}>
            ▲
          </button>
          <button className="iconbtn" style={{ padding: "4px 8px" }} onClick={() => onMove(1)}>
            ▼
          </button>
        </div>
      )}
    </div>
  );
}

// ---------------- 本の詳細 ----------------
function BookScreen({
  bookId,
  books,
  stickies,
  onBack,
  onEdit,
  onQuickMemo,
  toast,
}: {
  bookId: string;
  books: Book[];
  stickies: Sticky[];
  onBack: () => void;
  onEdit: (id: string) => void;
  onQuickMemo: () => void;
  toast: (m: string) => void;
}) {
  const book = books.find((b) => b.id === bookId);
  const pages = useMemo(() => getSamplePages(bookId), [bookId]);
  const bookStickies = stickiesForBook(stickies, bookId);
  const placedStickies = bookStickies.filter((s) => s.placed);
  const unplacedStickies = bookStickies.filter((s) => !s.placed);

  const [tab, setTab] = useState<Tab>("read");
  const [overlay, setOverlay] = useState<Overlay>(null);
  const [pageIdx, setPageIdx] = useState(0);
  const [reshoot, setReshoot] = useState(false);
  // A5: 位置未定メモを行に配置中の対象id。
  const [placingId, setPlacingId] = useState<string | null>(null);

  if (!book) return null;

  const page = pages[pageIdx];
  // 撮り直しを再現するとOCR結果（lines）がずれる。
  const lines = useMemo(
    () => (page ? (reshoot ? perturb(page.lines) : page.lines) : []),
    [page, reshoot],
  );

  // --- 写真撮影 + OCR の状態 ---
  const [photo, setPhoto] = useState<{ url: string; lines: OcrLine[] } | null>(
    null,
  );
  const [photoPage, setPhotoPage] = useState<number | null>(null);
  const [ocrStatus, setOcrStatus] = useState<"idle" | "running" | "error">(
    "idle",
  );
  const [ocrProgress, setOcrProgress] = useState(0);
  const [ocrPhase, setOcrPhase] = useState("準備中");
  const fileRef = useRef<HTMLInputElement>(null);

  // 目印のあいまい一致で、あるページ上に付箋を復元（行番号には依存しない）。
  const computeAnchors = (pageNumber: number, lineTexts: string[]) => {
    const map = new Map<number, Sticky>();
    placedStickies
      .filter((s) => s.pageNumber === pageNumber)
      .forEach((s) => {
        const m = findBestLine(s.marker, lineTexts, 0.5);
        if (m) map.set(m.lineIndex, s);
      });
    return map;
  };

  const unplacedForPage = (pageNumber: number) =>
    unplacedStickies.filter((s) => s.pageNumber === pageNumber);

  const placing = placingId
    ? unplacedStickies.find((s) => s.id === placingId) ?? null
    : null;

  // サンプルページ（撮影の再現）側のアンカーと位置未定メモ。
  const sampleAnchors = useMemo(
    () =>
      page ? computeAnchors(page.pageNumber, lines) : new Map<number, Sticky>(),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [page, lines, placedStickies],
  );
  const samplePageUnplaced = page ? unplacedForPage(page.pageNumber) : [];

  // 行タップの共通処理（サンプル / 写真で共用）。
  const handleTap = (lineTexts: string[], i: number, pageNumber: number) => {
    if (normalize(lineTexts[i] ?? "") === "") return;
    const before = lineTexts.slice(Math.max(0, i - 2), i);
    const after = lineTexts.slice(i + 1, i + 3);

    // 配置モード中: 位置未定メモをこの行に配置する。
    if (placing) {
      placeSticky(placing.id, {
        marker: lineTexts[i],
        clipBefore: before,
        clipAfter: after,
      });
      const rest = unplacedForPage(pageNumber).filter(
        (s) => s.id !== placing.id,
      );
      setPlacingId(rest[0]?.id ?? null);
      toast(
        rest.length > 0
          ? `✓ 配置しました（残り ${rest.length} 件）`
          : "✓ すべて配置しました",
      );
      return;
    }

    const anchors = computeAnchors(pageNumber, lineTexts);
    if (anchors.has(i)) {
      onEdit(anchors.get(i)!.id);
      return;
    }
    addSticky({
      bookId,
      pageNumber,
      marker: lineTexts[i],
      clipBefore: before,
      clipAfter: after,
    });
    toast("⚡ 付箋をつけました");
  };

  // --- OCR 実行 ---
  const runOcr = async (source: File | HTMLCanvasElement, url: string) => {
    setTab("read");
    setOcrStatus("running");
    setOcrProgress(0);
    setOcrPhase("準備中");
    setPlacingId(null);
    try {
      const res = await recognizeImage(source, (p, status) => {
        setOcrProgress(p);
        setOcrPhase(status);
      });
      setPhoto({ url, lines: res.lines });
      setPhotoPage(res.pageNumber);
      setOcrStatus("idle");
    } catch (err) {
      console.error(err);
      setOcrStatus("error");
    }
  };

  const onPickFile = async (e: ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0];
    e.target.value = "";
    if (!f) return;
    // 先に前処理（グレースケール＋コントラスト）してからOCRへ。
    setTab("read");
    setOcrStatus("running");
    setOcrProgress(0);
    setOcrPhase("画像を準備中");
    setPlacingId(null);
    try {
      const { displayUrl, ocrCanvas } = await prepareForOcr(f);
      await runOcr(ocrCanvas, displayUrl);
    } catch (err) {
      console.error(err);
      setOcrStatus("error");
    }
  };

  const runSampleOcr = () => {
    if (!page) return;
    const canvas = renderPageToCanvas(page);
    runOcr(canvas, canvas.toDataURL("image/png"));
  };

  const closePhoto = () => {
    setPhoto(null);
    setPhotoPage(null);
    setPlacingId(null);
  };

  // 写真側のアンカー・位置未定メモ。
  const photoLineTexts = photo ? photo.lines.map((l) => l.text) : [];
  const photoAnchors =
    photo && photoPage != null
      ? computeAnchors(photoPage, photoLineTexts)
      : new Map<number, Sticky>();
  const photoUnplacedCount =
    photo && photoPage != null ? unplacedForPage(photoPage).length : 0;

  return (
    <>
      <div className="topbar">
        <button className="iconbtn" onClick={onBack}>
          ‹ 本棚
        </button>
        <h1>{book.title}</h1>
      </div>

      <div className="content">
        <input
          ref={fileRef}
          type="file"
          accept="image/*"
          capture="environment"
          style={{ display: "none" }}
          onChange={onPickFile}
        />

        {tab === "list" ? (
          <ListTab
            placed={placedStickies}
            unplaced={unplacedStickies}
            onEdit={onEdit}
            onMove={(id, dir) => moveSticky(id, dir)}
          />
        ) : ocrStatus === "running" ? (
          <OcrLoading progress={ocrProgress} phase={ocrPhase} />
        ) : ocrStatus === "error" ? (
          <div className="empty">
            <div className="big">⚠️</div>
            読み取りに失敗しました。
            <br />
            明るい場所で、ページが正面になるように撮ってください。
            <div style={{ marginTop: 18 }}>
              <button
                className="btn-primary"
                style={{ maxWidth: 200, margin: "0 auto" }}
                onClick={() => setOcrStatus("idle")}
              >
                戻る
              </button>
            </div>
          </div>
        ) : photo ? (
          <PhotoReader
            imageUrl={photo.url}
            lines={photo.lines}
            pageNumber={photoPage}
            onPageNumber={setPhotoPage}
            anchors={photoAnchors}
            unplacedCount={photoUnplacedCount}
            placing={placing}
            onStartPlacing={() =>
              photoPage != null &&
              setPlacingId(unplacedForPage(photoPage)[0]?.id ?? null)
            }
            onCancelPlacing={() => setPlacingId(null)}
            onTapIndex={(i) =>
              photoPage != null && handleTap(photoLineTexts, i, photoPage)
            }
            onRetake={() => fileRef.current?.click()}
            onBackToSample={closePhoto}
          />
        ) : (
          <>
            <div className="capture-bar">
              <button
                className="capture-btn"
                onClick={() => fileRef.current?.click()}
              >
                📷 カメラで撮る
              </button>
              <button className="capture-btn ghost" onClick={runSampleOcr}>
                🧪 サンプル画像でOCR
              </button>
            </div>
            <p className="capture-tip">
              📸 コツ: 片方のページだけを正面から・明るく・なるべく平らに
            </p>
            <ReadTab
              page={page}
              lines={lines}
              anchors={sampleAnchors}
              pageIdx={pageIdx}
              pageCount={pages.length}
              reshoot={reshoot}
              pageUnplaced={samplePageUnplaced}
              placing={placing}
              onStartPlacing={() =>
                setPlacingId(samplePageUnplaced[0]?.id ?? null)
              }
              onCancelPlacing={() => setPlacingId(null)}
              onReshoot={() => setReshoot((r) => !r)}
              onPrev={() => {
                setPageIdx((i) => Math.max(0, i - 1));
                setReshoot(false);
                setPlacingId(null);
              }}
              onNext={() => {
                setPageIdx((i) => Math.min(pages.length - 1, i + 1));
                setReshoot(false);
                setPlacingId(null);
              }}
              onTapLine={(i) => page && handleTap(lines, i, page.pageNumber)}
            />
          </>
        )}
      </div>

      <div className="bottombar">
        <button
          className={tab === "read" ? "active" : ""}
          onClick={() => setTab("read")}
        >
          <span className="ic">📷</span>撮影
        </button>
        <button
          className={tab === "list" ? "active" : ""}
          onClick={() => setTab("list")}
        >
          <span className="ic">🏷️</span>一覧
        </button>
        <button onClick={onQuickMemo}>
          <span className="ic">✍️</span>メモ
        </button>
        <button onClick={() => setOverlay("flip")}>
          <span className="ic">📖</span>パラパラ
        </button>
        <button onClick={() => setOverlay("review")}>
          <span className="ic">🧠</span>復習
        </button>
      </div>

      {overlay === "flip" && (
        <FlipMode
          stickies={placedStickies}
          bookTitle={book.title}
          onClose={() => setOverlay(null)}
        />
      )}
      {overlay === "review" && (
        <ReviewScreen
          stickies={placedStickies}
          onClose={() => setOverlay(null)}
        />
      )}
    </>
  );
}

function ReadTab({
  page,
  lines,
  anchors,
  pageIdx,
  pageCount,
  reshoot,
  pageUnplaced,
  placing,
  onStartPlacing,
  onCancelPlacing,
  onReshoot,
  onPrev,
  onNext,
  onTapLine,
}: {
  page: { pageNumber: number } | undefined;
  lines: string[];
  anchors: Map<number, Sticky>;
  pageIdx: number;
  pageCount: number;
  reshoot: boolean;
  pageUnplaced: Sticky[];
  placing: Sticky | null;
  onStartPlacing: () => void;
  onCancelPlacing: () => void;
  onReshoot: () => void;
  onPrev: () => void;
  onNext: () => void;
  onTapLine: (i: number) => void;
}) {
  if (!page) {
    return (
      <div className="empty">
        <div className="big">📷</div>
        この本にはまだサンプルページがありません。
        <br />
        （カメラ撮影は次のステップで対応予定）
      </div>
    );
  }

  return (
    <>
      <div className="row" style={{ justifyContent: "space-between", marginBottom: 10 }}>
        <span className="page-chip">🔎 ページ {page.pageNumber} を認識</span>
        <button
          className="iconbtn"
          style={reshoot ? { background: "var(--accent)", color: "#fff", borderColor: "var(--accent)" } : undefined}
          onClick={onReshoot}
        >
          {reshoot ? "✓ 撮り直し再現中" : "📷 撮り直しを再現"}
        </button>
      </div>

      {placing ? (
        <div className="place-bar">
          <div className="pb-txt">
            <small>どの行の話？ タップで配置</small>
            <b>📝 {placing.heading}</b>
          </div>
          <button className="pb-cancel" onClick={onCancelPlacing}>
            やめる
          </button>
        </div>
      ) : (
        pageUnplaced.length > 0 && (
          <button className="unplaced-banner" onClick={onStartPlacing}>
            <span className="ub-ic">📝</span>
            <span className="ub-txt">
              このページに位置未定のメモが <b>{pageUnplaced.length}</b> 件
            </span>
            <span className="ub-go">配置する ›</span>
          </button>
        )
      )}

      <div className="page-sheet">
        {lines.map((l, i) => {
          const st = anchors.get(i);
          const blank = normalize(l) === "";
          return (
            <div
              key={i}
              className={
                "line" +
                (blank ? " blank" : " tappable") +
                (st ? " has-sticky" : "")
              }
              style={st ? { ["--sticky-c" as any]: cvar(st.color) } : undefined}
              onClick={() => onTapLine(i)}
            >
              {l}
              {st && <span className="tab">{"★".repeat(st.importance)}</span>}
            </div>
          );
        })}
      </div>

      <p className="hint">
        {placing
          ? "メモを貼る行をタップしてください"
          : "行をタップすると一瞬で付箋がつきます（メモは後からでOK）"}
      </p>

      <div className="pager">
        <button onClick={onPrev} disabled={pageIdx === 0}>
          ‹ 前のページ
        </button>
        <button onClick={onNext} disabled={pageIdx >= pageCount - 1}>
          次のページ ›
        </button>
      </div>
    </>
  );
}

function ListTab({
  placed,
  unplaced,
  onEdit,
  onMove,
}: {
  placed: Sticky[];
  unplaced: Sticky[];
  onEdit: (id: string) => void;
  onMove: (id: string, dir: -1 | 1) => void;
}) {
  if (placed.length === 0 && unplaced.length === 0) {
    return (
      <div className="empty">
        <div className="big">🏷️</div>
        まだ付箋がありません。
        <br />
        「撮影」タブでページの行をタップしてみましょう。
      </div>
    );
  }

  // 小口（こぐち）ビュー: 本の側面に見立てた付箋の位置 B2 / B4
  const pagesWithStickies = Array.from(
    new Set(placed.map((s) => s.pageNumber)),
  ).sort((a, b) => a - b);

  return (
    <>
      {unplaced.length > 0 && (
        <>
          <div className="section-label">
            位置未定のメモ {unplaced.length} 件（本を撮って配置）
          </div>
          {unplaced.map((s) => (
            <StickyRow
              key={s.id}
              s={s}
              unplaced
              onClick={() => onEdit(s.id)}
            />
          ))}
        </>
      )}

      {placed.length > 0 && (
        <>
          <div className="section-label">小口ビュー（本の側面）</div>
          <div className="edge">
            {pagesWithStickies.map((pn) => (
              <div className="tabrow" key={pn}>
                <span className="pn">p.{pn}</span>
                {placed
                  .filter((s) => s.pageNumber === pn)
                  .map((s) => (
                    <button
                      key={s.id}
                      className="t"
                      style={{
                        background: cvar(s.color),
                        width: 22 + s.importance * 8,
                        border: 0,
                      }}
                      onClick={() => onEdit(s.id)}
                      title={s.heading}
                    />
                  ))}
              </div>
            ))}
          </div>

          <div className="section-label">付箋 {placed.length} 件</div>
          {placed.map((s) => (
            <StickyRow
              key={s.id}
              s={s}
              onClick={() => onEdit(s.id)}
              onMove={(dir) => onMove(s.id, dir)}
            />
          ))}
        </>
      )}
    </>
  );
}

function OcrLoading({ progress, phase }: { progress: number; phase: string }) {
  const pct = Math.round(progress * 100);
  return (
    <div className="empty">
      <div className="big">🔎</div>
      <div style={{ fontWeight: 700, color: "var(--ink)", marginBottom: 12 }}>
        {phase}… {pct}%
      </div>
      <div className="ocr-progress">
        <div className="ocr-progress-bar" style={{ width: `${pct}%` }} />
      </div>
      <div style={{ marginTop: 12, fontSize: 12 }}>
        初回は日本語の辞書（数MB）を読み込むため少し時間がかかります
      </div>
    </div>
  );
}

// ---------------- 本の追加 ----------------
function AddBookModal({
  onClose,
  onCreate,
}: {
  onClose: () => void;
  onCreate: (b: Book) => void;
}) {
  const [title, setTitle] = useState("");
  const [author, setAuthor] = useState("");
  const [isbn, setIsbn] = useState("");

  const create = () => {
    if (!title.trim()) return;
    const b = addBook({ title, author, isbn });
    onCreate(b);
  };

  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <div className="sheet" onClick={(e) => e.stopPropagation()}>
        <div className="grip" />
        <p className="marker">本を追加</p>
        <div className="modal-form">
          <label>タイトル</label>
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="例）オペレーティングシステム"
            autoFocus
          />
          <label>著者（任意）</label>
          <input value={author} onChange={(e) => setAuthor(e.target.value)} />
          <label>ISBN（任意・バーコード読取は本番で対応）</label>
          <input
            value={isbn}
            onChange={(e) => setIsbn(e.target.value)}
            placeholder="978-..."
            inputMode="numeric"
          />
        </div>
        <div className="sheet-actions">
          <button className="btn-primary" onClick={create}>
            追加する
          </button>
        </div>
      </div>
    </div>
  );
}

// ---------------- クイックメモ（写真なし A5） ----------------
function QuickMemoSheet({
  book,
  onClose,
  toast,
}: {
  book: Book;
  onClose: () => void;
  toast: (m: string) => void;
}) {
  const [pageStr, setPageStr] = useState("");
  const [memo, setMemo] = useState("");
  const baseRef = useRef(memo);
  const { listening, isSupported, start, stop } = useSpeech((text) => {
    const base = baseRef.current;
    setMemo((base ? base + " " : "") + text);
  });

  const page = parseInt(pageStr, 10);
  const canSave = !!memo.trim() && Number.isFinite(page) && page > 0;

  const save = (keepOpen: boolean) => {
    if (!canSave) return;
    addQuickMemo({ bookId: book.id, pageNumber: page, memo: memo.trim() });
    toast("📝 メモを保存（あとで本を撮ると配置できます）");
    setMemo("");
    baseRef.current = "";
    if (!keepOpen) onClose();
  };

  const toggleMic = () => {
    if (listening) stop();
    else {
      baseRef.current = memo;
      start();
    }
  };

  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <div className="sheet" onClick={(e) => e.stopPropagation()}>
        <div className="grip" />
        <p className="marker">✍️ 写真なしでメモ</p>
        <p style={{ fontSize: 13, color: "var(--ink-soft)", margin: "0 0 14px" }}>
          📘 {book.title}
        </p>

        <div className="modal-form">
          <label>ページ番号</label>
          <input
            value={pageStr}
            onChange={(e) => setPageStr(e.target.value.replace(/[^0-9]/g, ""))}
            placeholder="例）12"
            inputMode="numeric"
            style={{ fontSize: 20, fontWeight: 700, letterSpacing: 2 }}
            autoFocus
          />
        </div>

        <p className="field-label" style={{ marginTop: 14 }}>
          メモ
        </p>
        <textarea
          className="memo-input"
          placeholder="覚えておきたいことをメモ（行の指定は後で）"
          value={memo}
          onChange={(e) => setMemo(e.target.value)}
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

        <div className="sheet-actions">
          <button
            className="btn-danger"
            style={{ opacity: canSave ? 1 : 0.4 }}
            onClick={() => save(true)}
          >
            保存して続ける
          </button>
          <button
            className="btn-primary"
            style={{ opacity: canSave ? 1 : 0.4 }}
            onClick={() => save(false)}
          >
            保存して閉じる
          </button>
        </div>
      </div>
    </div>
  );
}
