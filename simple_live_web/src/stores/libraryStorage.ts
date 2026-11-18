import type { Library } from "../types/library";
export const emptyLibrary = (): Library => ({
  follows: [],
  histories: [],
  tags: [],
  blocked: [],
});

const storageKey = "simple-live-web.library.v1";

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

export function loadLibrary(): { data: Library; error: string } {
  try {
    const raw = localStorage.getItem(storageKey);
    return {
      data: raw ? validate(JSON.parse(raw)) : emptyLibrary(),
      error: "",
    };
  } catch {
    return {
      data: emptyLibrary(),
      error:
        "本地数据无法读取，已停止写入。请先导出原始数据备份，再清除损坏的数据。",
    };
  }
}

export function saveLibrary(data: Library) {
  try {
    localStorage.setItem(storageKey, JSON.stringify(validate(data)));
  } catch {
    throw new Error("保存失败，浏览器存储空间不足或不可用；原有数据未更改");
  }
}

export function rawLibrary(): string {
  return localStorage.getItem(storageKey) ?? "{}";
}

export function resetLibrary() {
  localStorage.removeItem(storageKey);
}
