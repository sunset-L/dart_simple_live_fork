import type { Source } from "../../types/playback";

export async function attachStream(
  video: HTMLVideoElement,
  source: Source,
  proxied: boolean,
  failed: () => void,
  current: () => boolean,
) {
  const url = proxied ? source.proxyUrl : source.url;
  let cleanup = () => {};
  if (source.format === "hls") {
    const Hls = (await import("hls.js")).default;
    if (!current()) return () => {};
    if (Hls.isSupported()) {
      const hls = new Hls({
        enableWorker: true,
        lowLatencyMode: true,
        backBufferLength: 30,
      });
      hls.on(Hls.Events.ERROR, (_, data) => {
        if (data.fatal) failed();
      });
      hls.loadSource(url);
      hls.attachMedia(video);
      cleanup = () => hls.destroy();
    } else if (video.canPlayType("application/vnd.apple.mpegurl"))
      video.src = url;
    else throw new Error("此浏览器不支持 HLS 播放");
  } else if (source.format === "flv") {
    const flvjs = (await import("flv.js")).default;
    if (!current()) return () => {};
    if (!flvjs.isSupported())
      throw new Error(
        "此浏览器不支持 FLV，请选择 HLS 线路或使用桌面 Chrome/Edge",
      );
    const flv = flvjs.createPlayer(
      { type: "flv", url, isLive: true },
      {
        enableWorker: false,
        lazyLoad: false,
        autoCleanupSourceBuffer: true,
        autoCleanupMaxBackwardDuration: 30,
        autoCleanupMinBackwardDuration: 10,
      },
    );
    flv.on(flvjs.Events.ERROR, failed);
    flv.attachMediaElement(video);
    flv.load();
    cleanup = () => flv.destroy();
  } else if (source.format === "native") video.src = url;
  else
    throw new Error(
      "此浏览器不支持当前视频格式，请选择 HLS 线路或使用桌面 Chrome/Edge",
    );
  return () => {
    cleanup();
    if (current()) {
      video.removeAttribute("src");
      video.load();
    }
  };
}
