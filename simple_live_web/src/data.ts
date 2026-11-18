import { strFromU8, strToU8, unzipSync, zipSync } from "fflate";

export const platforms = [
  {
    id: "bilibili",
    name: "哔哩哔哩",
    logo: "bilibili_2.png",
    url: "https://live.bilibili.com/",
  },
  {
    id: "douyu",
    name: "斗鱼直播",
    logo: "douyu.png",
    url: "https://www.douyu.com/",
  },
  {
    id: "huya",
    name: "虎牙直播",
    logo: "huya.png",
    url: "https://www.huya.com/",
  },
  {
    id: "douyin",
    name: "抖音直播",
    logo: "douyin.png",
    url: "https://live.douyin.com/",
  },
];
export interface Follow {
  id: string;
  roomId: string;
  siteId: string;
  userName: string;
  face: string;
  addTime: string;
  tag: string;
}
export interface History extends Omit<Follow, "addTime" | "tag"> {
  updateTime: string;
}
export interface Tag {
  id: string;
  tag: string;
  userId: string[];
}
export interface Library {
  follows: Follow[];
  histories: History[];
  tags: Tag[];
  blocked: string[];
}
export interface Room {
  roomId: string;
  siteId: string;
  title: string;
  cover: string;
  userName: string;
  online: number;
}
export interface Category {
  id: string;
  parentId: string;
  name: string;
  pic: string | null;
}
export interface CategoryGroup {
  id: string;
  name: string;
  children: Category[];
}
export type Selection = {
  follows: boolean;
  histories: boolean;
  blocked: boolean;
};
export type Archive = Record<string, Uint8Array>;
export const emptyLibrary = (): Library => ({
  follows: [],
  histories: [],
  tags: [],
  blocked: [],
});
const storageKey = "simple-live-web.library.v1";
const filenames = {
  follows: "SimpleLive_follows.json",
  tags: "SimpleLive_Tags.json",
  histories: "SimpleLive_histories.json",
  blocked: "SimpleLive_blocked_word.json",
};
const limit = 20 * 1024 * 1024;

export function safeImage(value: string | null | undefined): string {
  if (!value) return "/assets/logo.png";
  try {
    const url = new URL(value.startsWith("//") ? `https:${value}` : value);
    return ["http:", "https:"].includes(url.protocol)
      ? url.href
      : "/assets/logo.png";
  } catch {
    return "/assets/logo.png";
  }
}

export async function api<T>(
  path: string,
  body?: unknown,
  signal?: AbortSignal,
): Promise<T> {
  let response: Response;
  try {
    response = await fetch(`/api/${path}`, {
      method: body === undefined ? "GET" : "POST",
      headers: {
        "X-Simple-Live": "web",
        ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: signal
        ? AbortSignal.any([signal, AbortSignal.timeout(95000)])
        : AbortSignal.timeout(95000),
    });
  } catch (error) {
    if (signal?.aborted) throw error;
    throw new Error("无法连接本地服务，或请求超时");
  }
  let data;
  try {
    data = await response.json();
  } catch {
    throw new Error("本地服务未就绪或返回了无效数据");
  }
  if (!response.ok)
    throw new Error(data.error ?? `请求失败（${response.status}）`);
  return data as T;
}

function record(value: unknown): Record<string, unknown> {
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
function unique<T extends { id: string }>(items: T[]): T[] {
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

export function readArchive(bytes: Uint8Array): Archive {
  if (bytes.byteLength > limit) throw new Error("备份不能超过 20 MB");
  let size = 0,
    count = 0;
  const files = unzipSync(bytes, {
    filter: (file) => {
      size += file.originalSize;
      if (
        ++count > 100 ||
        size > limit ||
        file.name.includes("..") ||
        file.name.includes("\\")
      ) {
        throw new Error("备份解压大小或文件路径不合法");
      }
      return true;
    },
  });
  if (!Object.values(filenames).some((name) => files[name]))
    throw new Error("这不是 Simple Live 备份");
  return files;
}

export function restore(
  current: Library,
  files: Archive,
  selection: Selection,
  replace: boolean,
): Library {
  const incoming: Record<string, unknown> = { ...emptyLibrary() };
  const keys = Object.keys(filenames) as (keyof typeof filenames)[];
  let matched = false;
  for (const key of keys) {
    const selected = key === "tags" ? selection.follows : selection[key];
    if (selected && files[filenames[key]]) {
      incoming[key] = record(JSON.parse(strFromU8(files[filenames[key]]))).data;
      matched = true;
    }
  }
  if (!matched) throw new Error("备份中没有所选类型的数据，未修改本地数据");
  if (
    selection.follows &&
    !!files[filenames.follows] !== !!files[filenames.tags]
  ) {
    throw new Error("关注和标签文件必须同时存在，未修改本地数据");
  }
  const parsed = validate(incoming);
  const result = structuredClone(current);
  if (selection.follows && files[filenames.follows]) {
    result.follows = replace
      ? parsed.follows
      : unique([...current.follows, ...parsed.follows]);
    result.tags = replace
      ? parsed.tags
      : unique([
          ...current.tags,
          ...parsed.tags.map((tag) => ({
            ...tag,
            userId: [
              ...new Set([
                ...(current.tags.find((old) => old.id === tag.id)?.userId ??
                  []),
                ...tag.userId,
              ]),
            ],
          })),
        ]);
  }
  if (selection.histories && files[filenames.histories]) {
    const histories = replace ? [] : current.histories;
    result.histories = unique(
      [...histories, ...parsed.histories].sort(
        (a, b) => Date.parse(a.updateTime) - Date.parse(b.updateTime),
      ),
    );
  }
  if (selection.blocked && files[filenames.blocked]) {
    result.blocked = replace
      ? parsed.blocked
      : [...new Set([...current.blocked, ...parsed.blocked])];
  }
  return validate(result);
}

export function makeArchive(
  data: Library,
  selection: Selection,
  base: Archive = {},
): Uint8Array {
  const files = { ...base };
  for (const key of Object.keys(filenames) as (keyof typeof filenames)[]) {
    if (key === "tags" ? selection.follows : selection[key]) {
      files[filenames[key]] = strToU8(JSON.stringify({ data: data[key] }));
    }
  }
  const size = Object.values(files).reduce(
    (sum, value) => sum + value.byteLength,
    0,
  );
  if (size > limit) throw new Error("备份不能超过 20 MB");
  return zipSync(files);
}
export function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 8192)
    binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
  return btoa(binary);
}
export function fromBase64(value: string): Uint8Array {
  return Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
}
export function download(data: Uint8Array | string, filename: string) {
  const url = URL.createObjectURL(
    new Blob([typeof data === "string" ? data : new Uint8Array(data)], {
      type: "application/octet-stream",
    }),
  );
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
