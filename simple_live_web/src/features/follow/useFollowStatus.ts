import { useEffect, useRef, useState } from "react";
import { updateFollowAvatars } from "../../stores/libraryStorage";
import { needsFollowAvatar, readFollowRoom, type FollowRoomState } from "./profile";
import type { Follow } from "../../types/library";

export interface FollowStatus extends Omit<FollowRoomState, "status"> {
  status: boolean | null;
  error?: string;
}

interface RefreshResult {
  total: number;
  failed: number;
}

export function useFollowStatus(
  follows: Pick<Follow, "id" | "siteId" | "roomId">[],
  enabled = true,
  onlyMissing = false,
) {
  const [statuses, setStatuses] = useState<Record<string, FollowStatus>>({});
  const statusesRef = useRef(statuses);
  const [loading, setLoading] = useState(false);
  const [version, setVersion] = useState(0);
  const lastVersion = useRef(version);
  const manualRefresh = useRef<((result: RefreshResult) => void) | undefined>(
    undefined,
  );
  const rooms = JSON.stringify(
    follows.map(({ id, siteId, roomId }) => ({ id, siteId, roomId })),
  );
  useEffect(() => {
    if (!enabled) return;
    let onComplete = manualRefresh.current;
    manualRefresh.current = undefined;
    const currentItems = JSON.parse(rooms) as Pick<
      Follow,
      "id" | "siteId" | "roomId"
    >[];
    const isManualRefresh = version !== lastVersion.current;
    lastVersion.current = version;
    const items =
      onlyMissing && !isManualRefresh
        ? currentItems.filter((item) => !statusesRef.current[item.id])
        : currentItems;
    const controller = new AbortController();
    let animationTimer: ReturnType<typeof setTimeout> | undefined;
    let running = false;
    async function refresh() {
      if (running || controller.signal.aborted) return;
      running = true;
      const started = performance.now();
      setLoading(items.length > 0);
      const retained = Object.fromEntries(
        currentItems
          .filter((item) => statusesRef.current[item.id])
          .map((item) => [item.id, statusesRef.current[item.id]]),
      );
      statusesRef.current = retained;
      setStatuses(retained);
      let index = 0;
      let failed = 0;
      const avatars: { id: string; face: string }[] = [];
      async function worker() {
        while (index < items.length && !controller.signal.aborted) {
          const item = items[index++];
          let result: FollowStatus;
          try {
            const value = await readFollowRoom(
              item.siteId,
              item.roomId,
              true,
              controller.signal,
            );
            if (typeof value.status !== "boolean")
              throw new Error("开播状态数据无效");
            result = value;
            if (value.face && !needsFollowAvatar(value.face))
              avatars.push({ id: item.id, face: value.face });
          } catch (error) {
            failed++;
            result = {
              status: null,
              error: error instanceof Error ? error.message : "开播状态查询失败",
            };
          }
          if (!controller.signal.aborted) {
            const next = { ...statusesRef.current, [item.id]: result };
            statusesRef.current = next;
            setStatuses(next);
          }
        }
      }
      await Promise.all(
        Array.from({ length: Math.min(4, items.length) }, () => worker()),
      );
      if (!controller.signal.aborted) {
        if (avatars.length) void updateFollowAvatars(avatars);
        const complete = () => {
          if (controller.signal.aborted) return;
          running = false;
          setLoading(false);
          onComplete?.({ total: items.length, failed });
          onComplete = undefined;
        };
        const remaining = items.length
          ? Math.max(0, 600 - (performance.now() - started))
          : 0;
        if (remaining) animationTimer = setTimeout(complete, remaining);
        else complete();
      }
    }
    void refresh();
    return () => {
      controller.abort();
      clearTimeout(animationTimer);
    };
  }, [rooms, enabled, version, onlyMissing]);
  return {
    statuses,
    loading,
    refresh: (onComplete?: (result: RefreshResult) => void) => {
      if (!enabled || loading) return;
      manualRefresh.current = onComplete;
      setLoading(follows.length > 0);
      setVersion((value) => value + 1);
    },
  };
}
