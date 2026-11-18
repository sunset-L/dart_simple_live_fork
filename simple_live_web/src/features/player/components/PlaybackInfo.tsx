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
    const read = () => {
      const video = player?.video;
      if (!video) return;
      const quality = video.getVideoPlaybackQuality?.();
      setMetrics({
        resolution: `${video.videoWidth} × ${video.videoHeight}`,
        frames: quality
          ? `${quality.totalVideoFrames} / 丢帧 ${quality.droppedVideoFrames}`
          : "--",
        buffered: video.buffered.length
          ? `${Math.max(0, video.buffered.end(video.buffered.length - 1) - video.currentTime).toFixed(1)} 秒`
          : "0 秒",
      });
    };
    read();
    const timer = setInterval(read, 1000);
    return () => clearInterval(timer);
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
