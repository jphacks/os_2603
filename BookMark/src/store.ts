import { useSyncExternalStore } from "react";
import type { Book, Importance, Sticky, StickyColor } from "./types";
import { SAMPLE_BOOKS, SAMPLE_PAGES } from "./sampleData";

const KEY_BOOKS = "bookmark.books.v1";
const KEY_STICKIES = "bookmark.stickies.v1";
const KEY_SEEDED = "bookmark.seeded.v1";
const KEY_LASTBOOK = "bookmark.lastbook.v1";

interface State {
  books: Book[];
  stickies: Sticky[];
}

function load(): State {
  // 初回のみサンプル本を投入（空の状態で迷子にならないように）。
  if (!localStorage.getItem(KEY_SEEDED)) {
    localStorage.setItem(KEY_BOOKS, JSON.stringify(SAMPLE_BOOKS));
    localStorage.setItem(KEY_STICKIES, JSON.stringify([]));
    localStorage.setItem(KEY_SEEDED, "1");
  }
  const books: Book[] = JSON.parse(localStorage.getItem(KEY_BOOKS) || "[]");
  const rawStickies: Sticky[] = JSON.parse(
    localStorage.getItem(KEY_STICKIES) || "[]",
  );
  // 既存データの移行: placed が無い付箋は配置済みとみなす。
  const stickies = rawStickies.map((s) => ({
    ...s,
    placed: s.placed ?? true,
  }));
  return { books, stickies };
}

// 最後に開いた本（A5: 毎回選ばせない）。
export function getLastBookId(): string | null {
  return localStorage.getItem(KEY_LASTBOOK);
}
export function setLastBookId(id: string) {
  localStorage.setItem(KEY_LASTBOOK, id);
}

let state: State = load();
const listeners = new Set<() => void>();

function emit() {
  localStorage.setItem(KEY_BOOKS, JSON.stringify(state.books));
  localStorage.setItem(KEY_STICKIES, JSON.stringify(state.stickies));
  listeners.forEach((l) => l());
}

function subscribe(l: () => void) {
  listeners.add(l);
  return () => listeners.delete(l);
}

export function useStore(): State {
  return useSyncExternalStore(subscribe, () => state);
}

// ---- 読み取り ----

export function getSamplePages(bookId: string) {
  return SAMPLE_PAGES.filter((p) => p.bookId === bookId).sort(
    (a, b) => a.pageNumber - b.pageNumber,
  );
}

export function stickiesForBook(stickies: Sticky[], bookId: string): Sticky[] {
  return stickies
    .filter((s) => s.bookId === bookId)
    .sort((a, b) =>
      a.pageNumber !== b.pageNumber
        ? a.pageNumber - b.pageNumber
        : a.order - b.order,
    );
}

// ---- 書き込み ----

const uid = () => Math.random().toString(36).slice(2, 10);

export function addBook(input: {
  title: string;
  author?: string;
  isbn?: string;
}): Book {
  const book: Book = {
    id: "book-" + uid(),
    title: input.title.trim() || "無題の本",
    author: input.author?.trim() || undefined,
    isbn: input.isbn?.trim() || undefined,
    createdAt: Date.now(),
  };
  state = { ...state, books: [book, ...state.books] };
  emit();
  return book;
}

/** 付箋ごとの一言の見出し（本番はAI、試作品では簡易生成）。 */
export function makeHeading(memo: string, marker: string): string {
  const base = (memo.trim() || marker.trim()).replace(/\s+/g, "");
  const cleaned = base.replace(/^[0-9.\s　]+/, "");
  const head = cleaned.slice(0, 14);
  return head || "付箋";
}

const COLOR_CYCLE: StickyColor[] = [
  "yellow",
  "pink",
  "blue",
  "green",
  "purple",
];

export function addSticky(input: {
  bookId: string;
  pageNumber: number;
  marker: string;
  clipBefore: string[];
  clipAfter: string[];
}): Sticky {
  const existing = state.stickies.filter((s) => s.bookId === input.bookId);
  const color = COLOR_CYCLE[existing.length % COLOR_CYCLE.length];
  const now = Date.now();
  const sticky: Sticky = {
    id: "st-" + uid(),
    bookId: input.bookId,
    pageNumber: input.pageNumber,
    placed: true,
    marker: input.marker,
    clipBefore: input.clipBefore,
    clipAfter: input.clipAfter,
    memo: "",
    heading: makeHeading("", input.marker),
    color,
    importance: 2,
    order: now,
    createdAt: now,
    updatedAt: now,
  };
  state = { ...state, stickies: [...state.stickies, sticky] };
  emit();
  return sticky;
}

/**
 * 写真なしで先にメモだけ残す（A5）。位置未定（placed:false）で作成。
 * 後で本を撮って行をタップすると placeSticky で配置される。
 */
export function addQuickMemo(input: {
  bookId: string;
  pageNumber: number;
  memo: string;
}): Sticky {
  const existing = state.stickies.filter((s) => s.bookId === input.bookId);
  const color = COLOR_CYCLE[existing.length % COLOR_CYCLE.length];
  const now = Date.now();
  const sticky: Sticky = {
    id: "st-" + uid(),
    bookId: input.bookId,
    pageNumber: input.pageNumber,
    placed: false,
    marker: "",
    clipBefore: [],
    clipAfter: [],
    memo: input.memo,
    heading: makeHeading(input.memo, ""),
    color,
    importance: 2,
    order: now,
    createdAt: now,
    updatedAt: now,
  };
  state = { ...state, stickies: [...state.stickies, sticky] };
  emit();
  return sticky;
}

/** 位置未定のメモを、タップした行に配置する（A5）。 */
export function placeSticky(
  id: string,
  anchor: { marker: string; clipBefore: string[]; clipAfter: string[] },
) {
  updateSticky(id, {
    placed: true,
    marker: anchor.marker,
    clipBefore: anchor.clipBefore,
    clipAfter: anchor.clipAfter,
  });
}

export function updateSticky(id: string, patch: Partial<Sticky>) {
  state = {
    ...state,
    stickies: state.stickies.map((s) =>
      s.id === id ? { ...s, ...patch, updatedAt: Date.now() } : s,
    ),
  };
  emit();
}

export function setMemo(id: string, memo: string) {
  const s = state.stickies.find((x) => x.id === id);
  if (!s) return;
  updateSticky(id, { memo, heading: makeHeading(memo, s.marker) });
}

export function setColor(id: string, color: StickyColor) {
  updateSticky(id, { color });
}

export function setImportance(id: string, importance: Importance) {
  updateSticky(id, { importance });
}

export function deleteSticky(id: string) {
  state = { ...state, stickies: state.stickies.filter((s) => s.id !== id) };
  emit();
}

/** 付箋の並べ替え（A18）。同じ本の中で order を入れ替える。 */
export function moveSticky(id: string, direction: -1 | 1) {
  const s = state.stickies.find((x) => x.id === id);
  if (!s) return;
  const siblings = stickiesForBook(state.stickies, s.bookId);
  const idx = siblings.findIndex((x) => x.id === id);
  const target = siblings[idx + direction];
  if (!target) return;
  const a = s.order;
  updateSticky(s.id, { order: target.order });
  updateSticky(target.id, { order: a });
}
