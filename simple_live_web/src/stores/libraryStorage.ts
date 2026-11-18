import type { Library } from "../types/library";
import { get, post } from "../services/apiClient";
export const emptyLibrary = (): Library => ({
  follows: [],
  histories: [],
  tags: [],
  blocked: [],
});

const storageKey = "simple-live-web.library.v1";
const migrationKey = `${storageKey}.migrated`;
const changeKey = `${storageKey}.changed`;
const listeners = new Set<() => void>();
let cached = { data: emptyLibrary(), error: "", corrupt: false };
let revision = "";
let raw = "{}";
let ready = false;
let writing = false;
let legacyCorrupt = false;
let initializing: Promise<void> | undefined;
let refreshing: Promise<void> | undefined;

interface StoredLibrary {
  revision: string;
  data: unknown;
  error?: string;
  raw?: string;
}

export function record(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value))
    throw new Error("备份数据格式错误");
  return value as Record<string, unknown>;
}

function text(value: unknown, allowEmpty = false): string {
  if (
    typeof value !== "string" ||
    value.length > 10000 ||
    (!allowEmpty && !value.trim())
  )
    throw new Error("备份字段无效");
  return value;
}

function list(value: unknown): unknown[] {
  if (!Array.isArray(value) || value.length > 50000)
    throw new Error("备份列表无效或过大");
  return value;
}

function date(value: unknown): string {
  const result = text(value);
  if (!Number.isFinite(Date.parse(result))) throw new Error("备份日期无效");
  return result;
}

function user(value: unknown) {
  const item = record(value);
  const siteId = text(item.siteId),
    roomId = text(item.roomId),
    id = text(item.id);
  if (id !== `${siteId}_${roomId}`) throw new Error("备份中的房间标识不一致");
  return {
    id,
    roomId,
    siteId,
    userName: text(item.userName, true),
    face: text(item.face, true),
  };
}

export function unique<T extends { id: string }>(items: T[]): T[] {
  return [...new Map(items.map((item) => [item.id, item])).values()];
}

export function validate(value: unknown): Library {
  const data = record(value);
  return {
    follows: unique(
      list(data.follows).map((value) => {
        const item = record(value);
        return {
          ...user(item),
          addTime: date(item.addTime),
          tag: item.tag == null ? "全部" : text(item.tag, true),
        };
      }),
    ),
    histories: unique(
      list(data.histories).map((value) => ({
        ...user(value),
        updateTime: date(record(value).updateTime),
      })),
    ),
    tags: unique(
      list(data.tags).map((value) => {
        const item = record(value);
        return {
          id: text(item.id),
          tag: text(item.tag),
          userId: list(item.userId).map((id) => text(id)),
        };
      }),
    ),
    blocked: [
      ...new Set(list(data.blocked).map((value) => text(value).trim())),
    ].filter(Boolean),
  };
}

export function loadLibrary(): { data: Library; error: string; corrupt: boolean } {
  return cached;
}

function publish() {
  listeners.forEach((listener) => listener());
}

function accept(value: StoredLibrary) {
  if (typeof value.revision !== "string")
    throw new Error("本地服务返回了无效数据");
  const data = value.data === null ? emptyLibrary() : validate(value.data);
  revision = value.revision;
  raw = value.raw ?? JSON.stringify(data);
  cached = { data, error: value.error ?? "", corrupt: Boolean(value.error) };
  publish();
}

function changed() {
  try {
    localStorage.setItem(changeKey, revision);
  } catch {
    // Disk persistence does not depend on browser storage being available.
  }
}

function mergeLegacy(server: Library, legacy: Library): Library {
  const follows = unique([...legacy.follows, ...server.follows]);
  const histories = new Map(server.histories.map((item) => [item.id, item]));
  for (const item of legacy.histories) {
    const current = histories.get(item.id);
    if (!current || Date.parse(item.updateTime) > Date.parse(current.updateTime))
      histories.set(item.id, item);
  }
  const tags = [...server.tags];
  const existingFollows = new Set(server.follows.map((item) => item.id));
  for (const item of legacy.tags) {
    const index = tags.findIndex(
      (current) => current.id === item.id || current.tag === item.tag,
    );
    const userId = item.userId.filter((id) => !existingFollows.has(id));
    if (index === -1) tags.push({ ...item, userId });
    else
      tags[index] = {
        ...tags[index],
        userId: [...new Set([...tags[index].userId, ...userId])],
      };
  }
  return validate({
    follows,
    histories: [...histories.values()],
    tags,
    blocked: [...new Set([...server.blocked, ...legacy.blocked])],
  });
}

export function initializeLibrary(): Promise<void> {
  if (ready) return Promise.resolve();
  if (initializing) return initializing;
  initializing = (async () => {
    try {
      accept(await get<StoredLibrary>("library"));
      if (cached.error) {
        ready = true;
        return;
      }
      let legacy: string | null = null;
      try {
        if (localStorage.getItem(migrationKey) !== "1")
          legacy = localStorage.getItem(storageKey);
      } catch {
        /* Browser storage is optional for the new disk-backed library. */
      }
      if (legacy) {
        let data: Library;
        try {
          data = validate(JSON.parse(legacy));
        } catch {
          legacyCorrupt = true;
          raw = legacy;
          throw new Error("旧浏览器数据损坏，请先导出原始数据，再清除损坏数据。");
        }
        // Another tab can migrate at the same time; merge against its new revision.
        for (let attempt = 0; ; attempt++) {
          try {
            accept(
              await post<StoredLibrary>("library", {
                revision,
                data: mergeLegacy(cached.data, data),
              }),
            );
            break;
          } catch (error) {
            if (attempt >= 2) throw error;
            accept(await get<StoredLibrary>("library"));
            if (cached.error) throw new Error(cached.error);
          }
        }
        changed();
      }
      try {
        localStorage.setItem(migrationKey, "1");
      } catch {
        /* Repeating the merge is idempotent if storage is unavailable. */
      }
      ready = true;
    } catch (error) {
      ready = legacyCorrupt;
      cached = {
        ...cached,
        corrupt: legacyCorrupt || cached.corrupt,
        error: error instanceof Error ? error.message : "本地数据读取失败",
      };
    } finally {
      initializing = undefined;
      publish();
    }
  })();
  return initializing;
}

export function refreshLibrary(): Promise<void> {
  if (!ready) return initializeLibrary();
  if (writing || legacyCorrupt) return Promise.resolve();
  if (refreshing) return refreshing;
  refreshing = (async () => {
    const startedRevision = revision;
    try {
      const value = await get<StoredLibrary>("library");
      if (
        !writing &&
        revision === startedRevision &&
        (value.revision !== revision || cached.error)
      )
        accept(value);
    } catch (error) {
      if (!writing && revision === startedRevision) {
        cached = {
          ...cached,
          error: error instanceof Error ? error.message : "本地数据读取失败",
        };
        publish();
      }
    } finally {
      refreshing = undefined;
    }
  })();
  return refreshing;
}

export async function saveLibrary(data: Library) {
  if (!ready) throw new Error("正在读取本地数据，请稍候");
  if (cached.error) throw new Error(cached.error);
  if (writing) throw new Error("正在保存，请稍候再操作");
  const next = validate(data);
  writing = true;
  try {
    accept(await post<StoredLibrary>("library", { revision, data: next }));
    changed();
  } catch (error) {
    // A conflict reloads the latest data without overwriting another tab's edits.
    try {
      accept(await get<StoredLibrary>("library"));
    } catch {
      /* Keep the last readable copy if the server is unavailable. */
    }
    throw error;
  } finally {
    writing = false;
  }
}

export function rawLibrary(): string {
  return raw;
}

export async function resetLibrary() {
  if (!cached.corrupt) throw new Error("数据没有损坏，请先重新读取本地数据");
  if (writing) throw new Error("正在保存，请稍候再操作");
  writing = true;
  try {
    if (legacyCorrupt) {
      localStorage.removeItem(storageKey);
      localStorage.setItem(migrationKey, "1");
      legacyCorrupt = false;
      accept(await get<StoredLibrary>("library"));
    } else {
      accept(await post<StoredLibrary>("library", { revision, reset: true }));
    }
    changed();
  } finally {
    writing = false;
  }
}

export function watchLibrary(listener: () => void): () => void {
  listeners.add(listener);
  const reload = () => {
    if (document.visibilityState !== "hidden") void refreshLibrary();
  };
  const onStorage = (event: StorageEvent) => {
    if (event.key === changeKey) reload();
  };
  const timer = setInterval(reload, 5000);
  window.addEventListener("focus", reload);
  document.addEventListener("visibilitychange", reload);
  window.addEventListener("storage", onStorage);
  return () => {
    listeners.delete(listener);
    clearInterval(timer);
    window.removeEventListener("focus", reload);
    document.removeEventListener("visibilitychange", reload);
    window.removeEventListener("storage", onStorage);
  };
}
