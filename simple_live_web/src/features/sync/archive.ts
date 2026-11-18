import { strFromU8, strToU8, unzipSync, zipSync } from "fflate";
import type { Library, Selection, Archive } from "../../types/library";
import { accountSites, type AccountCredentials } from "../../types/accounts";
import {
  emptyLibrary,
  record,
  unique,
  validate,
} from "../../stores/libraryStorage";
const filenames = {
  follows: "SimpleLive_follows.json",
  tags: "SimpleLive_Tags.json",
  histories: "SimpleLive_histories.json",
  blocked: "SimpleLive_blocked_word.json",
};
const accountFiles = {
  bilibili: { name: "SimpleLive_bilibili_account.json", field: "cookie" },
  douyu: { name: "SimpleLive_douyu_account.json", field: "auth" },
  douyin: { name: "SimpleLive_douyin_account.json", field: "cookie" },
} as const;

const limit = 20 * 1024 * 1024;

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
  if (![...Object.values(filenames), ...Object.values(accountFiles).map((file) => file.name)]
    .some((name) => files[name]))
    throw new Error("这不是 Simple Live 备份");
  return files;
}

export function hasLibraryData(files: Archive, selection: Selection) {
  return (Object.keys(filenames) as (keyof typeof filenames)[]).some((key) =>
    (key === "tags" ? selection.follows : selection[key]) && !!files[filenames[key]],
  );
}

export function readAccounts(files: Archive, selection: Selection): AccountCredentials {
  const result: AccountCredentials = {};
  for (const site of accountSites) {
    const file = accountFiles[site];
    if (!selection[site] || !files[file.name]) continue;
    try {
      const value = record(record(JSON.parse(strFromU8(files[file.name]))).data)[file.field];
      if (typeof value !== "string" || value.length > 50000) throw new Error();
      result[site] = value;
    } catch {
      // JSON parser messages can contain fragments of private credentials.
      throw new Error("备份中的账号数据格式无效，未修改本地数据");
    }
  }
  return result;
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
  accounts: AccountCredentials = {},
): Uint8Array {
  const files = { ...base };
  for (const key of Object.keys(filenames) as (keyof typeof filenames)[]) {
    if (key === "tags" ? selection.follows : selection[key]) {
      files[filenames[key]] = strToU8(JSON.stringify({ data: data[key] }));
    }
  }
  for (const site of accountSites) {
    if (!selection[site]) continue;
    if (typeof accounts[site] !== "string") throw new Error("账号数据未读取，备份已取消");
    const file = accountFiles[site];
    files[file.name] = strToU8(JSON.stringify({ data: { [file.field]: accounts[site] } }));
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
