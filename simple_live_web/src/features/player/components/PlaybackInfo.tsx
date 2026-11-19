import { useEffect, useState } from "react";
import type Artplayer from "artplayer";
export function PlaybackInfo({
  player,
  status,
}: {
  player: Artplayer | null;
  status: string;
}) {
  const [metrics, setMetrics] = useState({
    resolution: "--",
    frames: "--",
    buffered: "--",
  });
  useEffect(() => {
    const video = player?.video;
    if (!video) return;
    let lastRead = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const readNow = () => {
      timer = undefined;
      lastRead = performance.now();
      const quality = video.getVideoPlaybackQuality?.();
      const buffered = video.buffered;
      const next = {
        resolution: `${video.videoWidth} × ${video.videoHeight}`,
        frames: quality
          ? `${quality.totalVideoFrames} / 丢帧 ${quality.droppedVideoFrames}`
          : "--",
        buffered: buffered.length
          ? `${Math.max(0, buffered.end(buffered.length - 1) - video.currentTime).toFixed(1)} 秒`
          : "0 秒",
      };
      setMetrics((previous) =>
        previous.resolution === next.resolution &&
        previous.frames === next.frames &&
        previous.buffered === next.buffered
          ? previous
          : next,
      );
    };
    const read = () => {
      const delay = 900 - (performance.now() - lastRead);
      if (delay <= 0) readNow();
      else if (timer === undefined) timer = setTimeout(readNow, delay);
    };
    readNow();
    const events = [
      "loadedmetadata",
      "durationchange",
      "timeupdate",
      "progress",
      "playing",
      "waiting",
      "pause",
      "seeking",
      "seeked",
    ] as const;
    for (const event of events) video.addEventListener(event, read);
    const observer = new ResizeObserver(read);
    observer.observe(video);
    return () => {
      clearTimeout(timer);
      for (const event of events) video.removeEventListener(event, read);
      observer.disconnect();
    };
  }, [player]);
  return (
    <dl className="playback-info">
      <dt>状态</dt>
      <dd>{status}</dd>
      <dt>分辨率</dt>
      <dd>{metrics.resolution}</dd>
      <dt>解码帧</dt>
      <dd>{metrics.frames}</dd>
      <dt>前向缓冲</dt>
      <dd>{metrics.buffered}</dd>
    </dl>
  );
}
