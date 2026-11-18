import { get } from "../../services/apiClient";
import { safeImage } from "../../services/media";
import { updateFollowAvatars } from "../../stores/libraryStorage";

export interface FollowRoomState {
  status: boolean;
  face?: string;
  cover?: string;
  title?: string;
  online?: number;
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

export async function hydrateFollowAvatar(siteId: string, roomId: string) {
  try {
    const value = await readFollowRoom(siteId, roomId, true);
    if (value.face && !needsFollowAvatar(value.face))
      await updateFollowAvatars([{ id: `${siteId}_${roomId}`, face: value.face }]);
  } catch {
    // The follow stays saved; visiting or refreshing its list retries the avatar.
  }
}
