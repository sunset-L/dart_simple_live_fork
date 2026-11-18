import { useEffect, useState } from "react";
import { get } from "../../services/apiClient";
import type { Follow } from "../../types/library";

export interface FollowStatus {
  status: boolean | null;
  error?: string;
}

export function useFollowStatus(follows: Follow[], enabled = true) {
  const [statuses, setStatuses] = useState<Record<string, FollowStatus>>({});
  const [loading, setLoading] = useState(false);
  const [version, setVersion] = useState(0);
  const rooms = JSON.stringify(
    follows.map(({ id, siteId, roomId }) => ({ id, siteId, roomId })),
  );
  useEffect(() => {
    if (!enabled) return;
    const items = JSON.parse(rooms) as Pick<Follow, "id" | "siteId" | "roomId">[];
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    let running = false;
    async function refresh() {
      if (
        running ||
        controller.signal.aborted ||
        document.visibilityState === "hidden"
      )
        return;
      running = true;
      clearTimeout(timer);
      setLoading(items.length > 0);
      setStatuses({});
      let index = 0;
      async function worker() {
        while (index < items.length && !controller.signal.aborted) {
          const item = items[index++];
          let result: FollowStatus;
          try {
            const value = await get<{ status: boolean }>(
              `live-status?${new URLSearchParams({
                site: item.siteId,
                roomId: item.roomId,
              })}`,
              controller.signal,
            );
            if (typeof value.status !== "boolean")
              throw new Error("开播状态数据无效");
            result = { status: value.status };
          } catch (error) {
            result = {
              status: null,
              error: error instanceof Error ? error.message : "开播状态查询失败",
            };
          }
          if (!controller.signal.aborted)
            setStatuses((previous) => ({ ...previous, [item.id]: result }));
        }
      }
      await Promise.all(
        Array.from({ length: Math.min(4, items.length) }, () => worker()),
      );
      running = false;
      if (!controller.signal.aborted) {
        setLoading(false);
        timer = setTimeout(() => void refresh(), 60000);
      }
    }
    const visible = () => {
      if (document.visibilityState !== "hidden") void refresh();
    };
    void refresh();
    document.addEventListener("visibilitychange", visible);
    return () => {
      controller.abort();
      clearTimeout(timer);
      document.removeEventListener("visibilitychange", visible);
    };
  }, [rooms, enabled, version]);
  return {
    statuses,
    loading,
    refresh: () => setVersion((value) => value + 1),
  };
}
