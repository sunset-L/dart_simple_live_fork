import { get, post } from "../../services/apiClient";
import { safeImage } from "../../services/media";
import { updateFollowAvatars } from "../../stores/libraryStorage";
import type { Follow } from "../../types/library";

export interface FollowRoomState {
  status: boolean;
  face?: string;
  cover?: string;
  title?: string;
  online?: number;
}

export interface FollowRoomBatchResult extends Omit<FollowRoomState, "status"> {
  id: string;
  status: boolean | null;
  error?: string;
}

const pendingCards = new Map<string, Promise<FollowRoomState>>();
const cardQueue: (() => void)[] = [];
let activeCards = 0;

export function readCardProfile(siteId: string, roomId: string) {
  const key = `${siteId}_${roomId}`;
  const existing = pendingCards.get(key);
  if (existing) return existing;
  const promise = new Promise<FollowRoomState>((resolve, reject) => {
    cardQueue.push(() => {
      activeCards++;
      void readFollowRoom(siteId, roomId, true)
        .then(resolve, reject)
        .finally(() => {
          activeCards--;
          pendingCards.delete(key);
          drainCards();
        });
    });
  });
  pendingCards.set(key, promise);
  drainCards();
  return promise;
}

function drainCards() {
  while (activeCards < 4 && cardQueue.length) cardQueue.shift()!();
}

export function needsFollowAvatar(face: string) {
  return safeImage(face) === "/assets/logo.png";
}

export function readFollowRoom(
  siteId: string,
  roomId: string,
  profile: boolean,
  signal?: AbortSignal,
) {
  return get<FollowRoomState>(
    `live-status?${new URLSearchParams({
      site: siteId,
      roomId,
      ...(profile ? { profile: "1" } : {}),
    })}`,
    signal,
  );
}

export function readFollowRooms(
  follows: Pick<Follow, "id" | "siteId" | "roomId">[],
  signal?: AbortSignal,
  fresh = false,
): Promise<FollowRoomBatchResult[]> {
  return (async () => {
    const results: FollowRoomBatchResult[] = [];
    for (let index = 0; index < follows.length; index += 100) {
      const batch = follows.slice(index, index + 100);
      try {
        const response = await post<{ items: FollowRoomBatchResult[] }>(
          "live-status/batch",
          { items: batch, fresh },
          signal,
        );
        const byId = new Map(response.items.map((item) => [item.id, item]));
        results.push(
          ...batch.map(
            (item) =>
              byId.get(item.id) ?? {
                id: item.id,
                status: null,
                error: "开播状态查询失败",
              },
          ),
        );
      } catch (error) {
        if (signal?.aborted) throw error;
        results.push(
          ...batch.map((item) => ({
            id: item.id,
            status: null,
            error:
              error instanceof Error ? error.message : "开播状态查询失败",
          })),
        );
      }
    }
    return results;
  })();
}

export async function hydrateFollowAvatar(siteId: string, roomId: string) {
  try {
    const value = await readFollowRoom(siteId, roomId, true);
    if (value.face && !needsFollowAvatar(value.face))
      await updateFollowAvatars([{ id: `${siteId}_${roomId}`, face: value.face }]);
  } catch {
    // The follow stays saved; visiting or refreshing its list retries the avatar.
  }
}
