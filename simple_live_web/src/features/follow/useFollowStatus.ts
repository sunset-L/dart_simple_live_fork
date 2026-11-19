import { useEffect, useRef, useState } from "react";
import { updateFollowAvatars } from "../../stores/libraryStorage";
import {
  needsFollowAvatar,
  readFollowRooms,
  type FollowRoomBatchResult,
  type FollowRoomState,
} from "./profile";
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
      let failed = 0;
      const avatars: { id: string; face: string }[] = [];
      let results: FollowRoomBatchResult[];
      try {
        results = await readFollowRooms(items, controller.signal);
      } catch (error) {
        if (controller.signal.aborted) return;
        results = items.map((item) => ({
          id: item.id,
          status: null,
          error:
            error instanceof Error ? error.message : "开播状态查询失败",
        }));
      }
      if (!controller.signal.aborted) {
        const next = { ...statusesRef.current };
        for (const result of results) {
          if (result.status !== true && result.status !== false) failed++;
          next[result.id] = result;
          if (result.face && !needsFollowAvatar(result.face))
            avatars.push({ id: result.id, face: result.face });
        }
        statusesRef.current = next;
        setStatuses(next);
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
