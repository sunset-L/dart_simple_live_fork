import { useCallback, useEffect, useRef, useState } from "react";
import { playbackApi } from "../../../services/playbackApi";
import type { Quality, RoomDetail, Source } from "../../../types/playback";

export function usePlaybackSession(site: string, roomId: string) {
  const [detail, setDetail] = useState<RoomDetail | null>(null);
  const [qualities, setQualities] = useState<Quality[]>([]);
  const [quality, setQuality] = useState<Quality | null>(null);
  const [sources, setSources] = useState<Source[]>([]);
  const [source, setSource] = useState<Source | null>(null);
  const [loading, setLoading] = useState(true);
  const [switching, setSwitching] = useState(false);
  const [error, setError] = useState("");
  const [reload, setReload] = useState(0);
  const request = useRef<AbortController | null>(null);
  const selected = useRef<Quality | null>(null);
  const line = useRef<Source | null>(null);
  const selections = useRef(
    new WeakMap<Source, { quality: Quality; sources: Source[] }>(),
  );
  const remember = (items: Source[], quality: Quality) => {
    for (const item of items)
      selections.current.set(item, { quality, sources: items });
  };
  line.current = source;
  const sameLine = (left: Source, right: Source) => {
    const a = new URL(left.url, location.href);
    const b = new URL(right.url, location.href);
    return a.host === b.host && left.format === right.format;
  };
  const choose = useCallback(
    async (next: Quality, target?: Source) => {
      request.current?.abort();
      const controller = new AbortController();
      request.current = controller;
      setSwitching(true);
      setError("");
      try {
        const result = await playbackApi.sources(
          site,
          roomId,
          next,
          controller.signal,
        );
        if (controller.signal.aborted) return;
        const previous = target ?? line.current;
        const desired =
          previous && result.items.find((item) => sameLine(item, previous));
        if (target && !desired)
          throw new Error("所选线路暂不可用，保留当前播放");
        selected.current = next;
        remember(result.items, next);
        setQuality(next);
        setSources(result.items);
        setSource(desired ?? result.items[0] ?? null);
      } catch (reason) {
        if (!controller.signal.aborted)
          setError(reason instanceof Error ? reason.message : "取流失败");
      } finally {
        if (!controller.signal.aborted) setSwitching(false);
      }
    },
    [site, roomId],
  );
  useEffect(() => {
    const controller = new AbortController();
    request.current?.abort();
    request.current = controller;
    setLoading(true);
    setSwitching(false);
    setError("");
    void (async () => {
      try {
        const room = await playbackApi.detail(site, roomId, controller.signal);
        if (controller.signal.aborted) return;
        setDetail(room);
        if (!room.status) {
          setSource(null);
          setQualities([]);
          setSources([]);
          setQuality(null);
          return;
        }
        const result = await playbackApi.qualities(
          site,
          roomId,
          controller.signal,
        );
        if (controller.signal.aborted) return;
        setQualities(result.items);
        const remembered = selected.current;
        const next = remembered
          ? result.items.find(
              (item) =>
                item.quality === remembered.quality &&
                item.sort === remembered.sort,
            )
          : result.items[0];
        if (!next) throw new Error("所选画质不可用，请手动选择清晰度");
        const urls = await playbackApi.sources(
          site,
          roomId,
          next,
          controller.signal,
        );
        if (controller.signal.aborted) return;
        selected.current = next;
        remember(urls.items, next);
        setQuality(next);
        setSources(urls.items);
        const previous = line.current;
        setSource(
          urls.items.find((item) => previous && sameLine(item, previous)) ??
            urls.items[0] ??
            null,
        );
      } catch (reason) {
        if (!controller.signal.aborted)
          setError(reason instanceof Error ? reason.message : "房间加载失败");
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    })();
    return () => {
      controller.abort();
      request.current?.abort();
    };
  }, [site, roomId, reload]);
  useEffect(() => {
    if (!source?.expiresAt || !quality) return;
    const remaining = Math.max(30000, source.expiresAt - Date.now() - 30000);
    const timer = setTimeout(
      () => void choose(quality),
      Math.min(remaining, 2147483647),
    );
    return () => clearTimeout(timer);
  }, [source, quality, choose]);
  return {
    detail,
    qualities,
    quality,
    sources,
    source,
    loading,
    switching,
    error,
    choose,
    confirm: (playing: Source) => {
      const selection = selections.current.get(playing);
      if (!selection) return;
      selected.current = selection.quality;
      setQuality(selection.quality);
      setSources(selection.sources);
      setSource(playing);
    },
    refresh: useCallback(() => setReload((value) => value + 1), []),
    selectLine: (target: Source) => quality && void choose(quality, target),
  };
}
