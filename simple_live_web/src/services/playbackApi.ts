import { get } from "./apiClient";
import type {
  DanmakuEvent,
  PlaybackAuthWarning,
  PlaybackSession,
  Quality,
  RoomDetail,
  Source,
} from "../types/playback";
export const playbackApi = {
  session: (
    site: string,
    roomId: string,
    quality?: Quality | null,
    signal?: AbortSignal,
  ) => {
    const query = new URLSearchParams({ site, roomId });
    if (quality) {
      query.set("qualityName", quality.quality);
      query.set("sort", String(quality.sort));
    }
    return get<PlaybackSession>(`playback/session?${query}`, signal);
  },
  detail: (site: string, roomId: string, signal?: AbortSignal) =>
    get<RoomDetail>(
      `playback/room?site=${encodeURIComponent(site)}&roomId=${encodeURIComponent(roomId)}`,
      signal,
    ),
  qualities: (site: string, roomId: string, signal?: AbortSignal) =>
    get<{ items: Quality[] }>(
      `playback/qualities?site=${encodeURIComponent(site)}&roomId=${encodeURIComponent(roomId)}`,
      signal,
    ),
  sources: (
    site: string,
    roomId: string,
    quality: Quality,
    signal?: AbortSignal,
  ) =>
    get<{
      quality: string;
      items: Source[];
      authWarning?: PlaybackAuthWarning;
    }>(
      `playback/source?${new URLSearchParams({ site, roomId, qualityName: quality.quality, sort: String(quality.sort) })}`,
      signal,
    ),
  danmakuUrl: (site: string, roomId: string) =>
    `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/ws/danmaku?site=${encodeURIComponent(site)}&roomId=${encodeURIComponent(roomId)}`,
  isEvent: (value: unknown): value is DanmakuEvent =>
    typeof value === "object" && value !== null && "type" in value,
};
