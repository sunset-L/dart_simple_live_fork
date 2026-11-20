export type Page =
  "home" | "follow" | "category" | "mine" | "sync" | "history" | "blocked" | "accounts";
export function playbackUrl(site: string, roomId: string) {
  return `/live/${encodeURIComponent(site)}/${encodeURIComponent(roomId)}`;
}
export interface ParsedLiveLink {
  site: "bilibili" | "douyu" | "huya" | "douyin";
  roomId: string;
}
const roomIdPattern = /^[A-Za-z0-9_-]{1,100}$/;
function hostIs(host: string, domain: string) {
  return host === domain || host.endsWith(`.${domain}`);
}
export function parseLiveLink(value: string): ParsedLiveLink | null {
  let url: URL;
  try {
    url = new URL(value.trim());
  } catch {
    return null;
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") return null;
  const host = url.hostname.toLowerCase();
  const first = url.pathname.split("/").filter(Boolean)[0] ?? "";
  if (hostIs(host, "bilibili.com") && roomIdPattern.test(first))
    return { site: "bilibili", roomId: first };
  if (hostIs(host, "douyu.com")) {
    const roomId = url.pathname.startsWith("/topic/")
      ? url.searchParams.get("rid") ?? ""
      : first;
    if (roomIdPattern.test(roomId)) return { site: "douyu", roomId };
  }
  if (hostIs(host, "huya.com") && roomIdPattern.test(first))
    return { site: "huya", roomId: first };
  if (host === "live.douyin.com" && roomIdPattern.test(first))
    return { site: "douyin", roomId: first };
  if (host === "webcast.amemv.com") {
    const reflow = url.pathname.match(/\/reflow\/([0-9]+)/);
    if (reflow) return { site: "douyin", roomId: reflow[1] };
  }
  return null;
}
export function isShortLiveLink(value: string) {
  try {
    const url = new URL(value.trim());
    return (
      (url.hostname === "b23.tv" || url.hostname === "v.douyin.com") &&
      (url.protocol === "http:" || url.protocol === "https:")
    );
  } catch {
    return false;
  }
}
const playbackTabs = new Map<string, Window>();
export function openPlayback(
  site: string,
  roomId: string,
  targetWindow?: Window | null,
) {
  const key = `${site}-${roomId}`;
  for (const [name, tab] of playbackTabs) {
    if (tab.closed) playbackTabs.delete(name);
  }
  const existing = playbackTabs.get(key);
  if (existing && !existing.closed) {
    existing.focus();
    return;
  }
  const tab =
    targetWindow && !targetWindow.closed
      ? targetWindow
      : window.open(
          playbackUrl(site, roomId),
          `simple-live-${site}-${roomId}`,
        );
  if (tab) {
    tab.location.replace(playbackUrl(site, roomId));
    tab.opener = null;
    playbackTabs.set(key, tab);
    tab.focus();
  }
}
