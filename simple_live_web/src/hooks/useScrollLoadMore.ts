import { useEffect, useRef, type CSSProperties } from "react";

export const scrollLoadTriggerStyle: CSSProperties = {
  minHeight: 28,
  alignItems: "center",
  gap: 8,
  color: "var(--muted)",
  fontSize: 12,
};

interface Options {
  hasMore: boolean;
  loading: boolean;
  onLoad: () => void;
  rootMargin?: string;
  debounceMs?: number;
}

export function useScrollLoadMore({
  hasMore,
  loading,
  onLoad,
  rootMargin = "240px 0px",
  debounceMs = 120,
}: Options) {
  const target = useRef<HTMLDivElement>(null);
  const loadingRef = useRef(loading);
  const hasMoreRef = useRef(hasMore);
  const onLoadRef = useRef(onLoad);
  const lockedRef = useRef(false);
  const sawLoadingRef = useRef(false);
  loadingRef.current = loading;
  hasMoreRef.current = hasMore;
  onLoadRef.current = onLoad;

  useEffect(() => {
    if (loading) sawLoadingRef.current = true;
    else if (sawLoadingRef.current) {
      sawLoadingRef.current = false;
      lockedRef.current = false;
    }
  }, [loading]);

  useEffect(() => {
    const node = target.current;
    if (!node || !hasMore) return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const observer = new IntersectionObserver(
      (entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return;
        clearTimeout(timer);
        timer = setTimeout(() => {
          if (
            lockedRef.current ||
            loadingRef.current ||
            !hasMoreRef.current
          )
            return;
          lockedRef.current = true;
          onLoadRef.current();
          window.setTimeout(() => {
            if (!sawLoadingRef.current && !loadingRef.current)
              lockedRef.current = false;
          }, 1000);
        }, debounceMs);
      },
      { rootMargin },
    );
    observer.observe(node);
    return () => {
      clearTimeout(timer);
      observer.disconnect();
    };
  }, [debounceMs, hasMore, loading, rootMargin]);

  return target;
}
