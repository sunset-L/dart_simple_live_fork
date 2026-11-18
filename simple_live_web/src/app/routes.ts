export type Page =
  "home" | "follow" | "category" | "mine" | "sync" | "history" | "blocked" | "accounts";
export function playbackUrl(site: string, roomId: string) {
  return `/live/${encodeURIComponent(site)}/${encodeURIComponent(roomId)}`;
}
const playbackTabs = new Map<string, Window>();
export function openPlayback(site: string, roomId: string) {
  const key = `${site}-${roomId}`;
  for (const [name, tab] of playbackTabs) {
    if (tab.closed) playbackTabs.delete(name);
  }
  const existing = playbackTabs.get(key);
  if (existing && !existing.closed) {
    existing.focus();
    return;
  }
  const tab = window.open(
    playbackUrl(site, roomId),
    `simple-live-${site}-${roomId}`,
  );
  if (tab) {
    tab.opener = null;
    playbackTabs.set(key, tab);
    tab.focus();
  }
}
