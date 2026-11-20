import type { Source } from "../../types/playback";
import { attachStream } from "./engine";

interface Events {
  sources: () => Source[];
  state: (text: string) => void;
  confirmed: (source: Source) => void;
  failure: (text: string) => void;
}

// Each load owns its engine and generation. Late events cannot replace a newer stream.
export function createStreamSession(video: HTMLVideoElement, events: Events) {
  let dispose: (() => void) | undefined;
  let stopped = false,
    generation = 0;
  let active: Source | null = null,
    previous: Source | null = null;
  let proxy = false,
    settled = false,
    faulting = false,
    firstFrame = false,
    idlePaused = false;
  let lastProgress = performance.now(),
    position = -1;
  let healthTimer: ReturnType<typeof setTimeout> | undefined;
  const attempted = new Set<Source>();

  function clearHealthTimer() {
    clearTimeout(healthTimer);
    healthTimer = undefined;
  }

  function scheduleHealthCheck() {
    clearHealthTimer();
    if (!active || faulting || idlePaused || video.paused) return;
    const check = () => {
      healthTimer = undefined;
      if (!active || faulting || idlePaused || video.paused) return;
      const remaining = 25000 - (performance.now() - lastProgress);
      if (remaining <= 0) fail();
      else healthTimer = setTimeout(check, remaining);
    };
    healthTimer = setTimeout(
      check,
      Math.max(1, 25000 - (performance.now() - lastProgress)),
    );
  }

  async function start(source: Source, useProxy: boolean) {
    const version = ++generation;
    clearHealthTimer();
    faulting = true;
    dispose?.();
    dispose = undefined;
    video.removeAttribute("src");
    video.load();
    active = source;
    attempted.add(source);
    proxy = useProxy;
    settled = firstFrame = faulting = false;
    lastProgress = performance.now();
    position = -1;
    events.state(idlePaused ? "已暂停" : "缓冲中");
    try {
      const cleanup = await attachStream(
        video,
        source,
        useProxy,
        () => {
          if (version === generation) fail();
        },
        () => !stopped && version === generation,
      );
      if (stopped || version !== generation) {
        cleanup();
        return;
      }
      dispose = cleanup;
      // Renewing a signed URL must not resume playback after an idle pause.
      if (idlePaused) {
        settled = true;
        return;
      }
      try {
        await video.play();
      } catch (error) {
        throw error;
      }
    } catch (error) {
      if (stopped || version !== generation) return;
      if (error instanceof DOMException && error.name === "NotAllowedError") {
        settled = true;
        events.state("点击播放");
      } else if (!(
        error instanceof DOMException && error.name === "AbortError"
      )) {
        fail();
      }
    }
  }
  function fail() {
    if (stopped || !active || faulting || idlePaused) return;
    faulting = true;
    clearHealthTimer();
    if (!proxy) {
      void start(active, true);
      return;
    }
    const next = events.sources().find((source) => !attempted.has(source));
    if (next) {
      void start(next, !next.direct);
      return;
    }
    if (previous && !attempted.has(previous)) {
      void start(previous, !previous.direct);
      return;
    }
    settled = true;
    events.state("播放失败");
    events.failure("播放失败，已尝试可用线路，请刷新取流或切换清晰度");
  }
  const playing = () => {
    if (!active || faulting) return;
    firstFrame = settled = true;
    lastProgress = performance.now();
    position = video.currentTime;
    scheduleHealthCheck();
    events.confirmed(active);
    events.state(proxy ? "播放中 · 代理" : "播放中 · 直连");
  };
  const error = () => {
    if (video.error) fail();
  };
  const play = () => {
    idlePaused = false;
    scheduleHealthCheck();
  };
  const progress = () => {
    if (video.currentTime === position) return;
    position = video.currentTime;
    lastProgress = performance.now();
  };
  const pause = () => {
    clearHealthTimer();
    if (settled) events.state("已暂停");
  };
  const waiting = () => {
    if (firstFrame) events.state("缓冲中");
  };
  video.addEventListener("play", play);
  video.addEventListener("playing", playing);
  video.addEventListener("timeupdate", progress);
  video.addEventListener("error", error);
  video.addEventListener("pause", pause);
  video.addEventListener("waiting", waiting);
  return {
    pauseForIdle() {
      idlePaused = true;
      clearHealthTimer();
      video.pause();
      events.state("已暂停");
    },
    load(source: Source) {
      if (source === active) return;
      if (firstFrame && active) previous = active;
      attempted.clear();
      void start(source, !source.direct);
    },
    stop() {
      generation++;
      faulting = true;
      clearHealthTimer();
      idlePaused = false;
      active = previous = null;
      dispose?.();
      dispose = undefined;
      video.removeAttribute("src");
      video.load();
      video.pause();
    },
    destroy() {
      stopped = true;
      generation++;
      clearHealthTimer();
      dispose?.();
      video.removeAttribute("src");
      video.load();
      video.removeEventListener("play", play);
      video.removeEventListener("playing", playing);
      video.removeEventListener("timeupdate", progress);
      video.removeEventListener("error", error);
      video.removeEventListener("pause", pause);
      video.removeEventListener("waiting", waiting);
    },
  };
}
