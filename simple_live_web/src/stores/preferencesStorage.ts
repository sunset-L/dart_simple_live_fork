import { useSyncExternalStore } from "react";
import { get, post, request } from "../services/apiClient";

export const themeColors = [
  { id: "blue", name: "蓝色", color: "#1677ff" },
  { id: "green", name: "绿色", color: "#52c41a" },
  { id: "teal", name: "青色", color: "#13c2c2" },
  { id: "rose", name: "玫红", color: "#eb2f96" },
  { id: "amber", name: "金色", color: "#faad14" },
  { id: "violet", name: "紫色", color: "#722ed1" },
] as const;
export const playerDefaults = {
  enabled: true,
  opacity: 0.9,
  size: 20,
  weight: 4,
  duration: 8,
  area: 0.8,
  topMargin: 0,
  verticalGap: 4,
  horizontalGap: 16,
  fortune: false,
  antiOverlap: true,
};
export type PlayerSettings = typeof playerDefaults;
interface WebdavSettings {
  url: string;
  username: string;
  password: string;
}
interface Preferences {
  mode: string;
  primaryColor: string;
  sidebarCollapsed: boolean;
  playbackSidebarCollapsed: boolean;
  player: PlayerSettings;
  webdav: WebdavSettings;
}
type PreferencePatch = Partial<Omit<Preferences, "player" | "webdav">> & {
  player?: Partial<PlayerSettings>;
  webdav?: Partial<WebdavSettings>;
};
interface StoredPreferences {
  data: PreferencePatch;
}

export function normalizeColor(value: string) {
  return (
    themeColors.find((item) => item.id === value)?.color ??
    (/^#[0-9a-f]{6}$/i.test(value) ? value : "#1677ff")
  );
}

function legacyPreferences(): PreferencePatch {
  const result: PreferencePatch = {};
  try {
    const mode = localStorage.getItem("simple-live-web.theme");
    if (mode && ["system", "light", "dark"].includes(mode)) result.mode = mode;
    const color = localStorage.getItem("simple-live-web.theme-color");
    if (color) result.primaryColor = normalizeColor(color);
    const collapsed = localStorage.getItem("simple-live-web.sidebar-collapsed");
    if (collapsed !== null) result.sidebarCollapsed = collapsed === "1";
    const raw = localStorage.getItem("simple-live-web.player.v1");
    if (raw) {
      const value = JSON.parse(raw);
      if (value && typeof value === "object" && !Array.isArray(value)) {
        const player: Partial<PlayerSettings> = {};
        for (const field of ["enabled", "fortune", "antiOverlap"] as const)
          if (typeof value[field] === "boolean") player[field] = value[field];
        const limits = {
          opacity: [0.1, 1],
          size: [8, 48],
          weight: [1, 9],
          duration: [1, 10],
          area: [0.1, 1],
          topMargin: [0, 48],
          verticalGap: [0, 40],
          horizontalGap: [0, 100],
        } as const;
        for (const field of Object.keys(limits) as (keyof typeof limits)[]) {
          const [min, max] = limits[field];
          if (typeof value[field] === "number" && Number.isFinite(value[field]))
            player[field] = Math.min(max, Math.max(min, value[field]));
        }
        result.player = player;
      }
    }
  } catch {
    // Invalid legacy fields do not prevent loading the authoritative disk copy.
  }
  return result;
}

function merge(left: PreferencePatch, right: PreferencePatch): PreferencePatch {
  return {
    ...left,
    ...right,
    player: { ...left.player, ...right.player },
    webdav: { ...left.webdav, ...right.webdav },
  };
}
const defaults: Preferences = {
  mode: "system",
  primaryColor: "#1677ff",
  sidebarCollapsed: false,
  playbackSidebarCollapsed: false,
  player: playerDefaults,
  webdav: { url: "", username: "", password: "" },
};
const migrationKey = "simple-live-web.preferences.v1.migrated";
const listeners = new Set<() => void>();
let stored = legacyPreferences();
let pending: PreferencePatch = {};
let inFlight: PreferencePatch = {};
let cached = { data: merge(defaults, stored) as Preferences, error: "" };
let ready = false;
let initializing: Promise<void> | undefined;
let refreshing: Promise<void> | undefined;
let writing = false;
let generation = 0;
let timer: ReturnType<typeof setTimeout> | undefined;

function publish(error = cached.error) {
  const data = merge(
    merge(merge(defaults, stored), inFlight),
    pending,
  ) as Preferences;
  if (JSON.stringify(data.player) === JSON.stringify(cached.data.player))
    data.player = cached.data.player;
  if (JSON.stringify(data.webdav) === JSON.stringify(cached.data.webdav))
    data.webdav = cached.data.webdav;
  cached = {
    data,
    error,
  };
  listeners.forEach((listener) => listener());
}
function accept(value: StoredPreferences) {
  if (!value.data || typeof value.data !== "object" || Array.isArray(value.data))
    throw new Error("本地服务返回了无效设置");
  stored = value.data;
}
function message(error: unknown) {
  return error instanceof Error ? error.message : "本地设置读写失败";
}

export function initializePreferences(): Promise<void> {
  if (ready) return Promise.resolve();
  if (initializing) return initializing;
  initializing = (async () => {
    try {
      const value = await get<StoredPreferences>("preferences");
      let legacy: PreferencePatch = {};
      try {
        if (localStorage.getItem(migrationKey) !== "1")
          legacy = legacyPreferences();
      } catch {
        /* Browser storage is optional. */
      }
      // Migrate only explicit old settings; a new origin must not seed defaults.
      accept(
        Object.keys(legacy).length
          ? await post<StoredPreferences>("preferences", {
              patch: legacy,
              onlyMissing: true,
            })
          : value,
      );
      try {
        localStorage.setItem(migrationKey, "1");
      } catch {
        /* The server-side missing-field merge is idempotent. */
      }
      ready = true;
      publish("");
    } catch (error) {
      publish(`设置读取失败：${message(error)}`);
    } finally {
      initializing = undefined;
    }
  })();
  return initializing;
}

export async function refreshPreferences() {
  if (!ready) return initializePreferences();
  if (writing || Object.keys(pending).length) return;
  if (refreshing) return refreshing;
  refreshing = (async () => {
    const started = generation;
    try {
      const value = await get<StoredPreferences>("preferences");
      if (started === generation && !writing && !Object.keys(pending).length) {
        accept(value);
        if (
          JSON.stringify(cached.data) !==
            JSON.stringify(merge(defaults, stored)) ||
          cached.error
        )
          publish("");
      }
    } catch (error) {
      if (started === generation && !writing && !Object.keys(pending).length)
        publish(`设置读取失败：${message(error)}`);
    } finally {
      refreshing = undefined;
    }
  })();
  return refreshing;
}

async function flush() {
  if (writing || !ready) return;
  writing = true;
  try {
    while (Object.keys(pending).length) {
      inFlight = pending;
      pending = {};
      try {
        accept(
          await request<StoredPreferences>("preferences", {
            method: "POST",
            keepalive: true,
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ patch: inFlight }),
          }),
        );
        inFlight = {};
        publish("");
      } catch (error) {
        inFlight = {};
        publish(`设置保存失败：${message(error)}`);
      }
    }
  } finally {
    writing = false;
  }
}

export function updatePreferences(patch: PreferencePatch) {
  if (!ready) {
    publish(cached.error || "正在读取本地设置，请稍候再操作");
    return;
  }
  generation++;
  pending = merge(pending, patch);
  publish("");
  clearTimeout(timer);
  timer = setTimeout(() => void flush(), 150);
}

function watchUpdates() {
  const onPageHide = () => void flush();
  window.addEventListener("pagehide", onPageHide);
  return () => {
    window.removeEventListener("pagehide", onPageHide);
  };
}

let stopWatching: (() => void) | undefined;
function subscribe(listener: () => void) {
  listeners.add(listener);
  stopWatching ??= watchUpdates();
  return () => {
    listeners.delete(listener);
    if (!listeners.size) {
      stopWatching?.();
      stopWatching = undefined;
    }
  };
}

export function usePreferences() {
  return useSyncExternalStore(subscribe, () => cached);
}
