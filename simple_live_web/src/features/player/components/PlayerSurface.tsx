import { useEffect, useRef } from "react";
import Artplayer from "artplayer";
import danmuku, {
  type Result as DanmakuRenderer,
} from "artplayer-plugin-danmuku";
import type { DanmakuMessage, Source, Quality } from "../../../types/playback";
import type { PlayerSettings } from "../../../stores/playerSettings";
import { createStreamSession } from "../streamSession";

export interface PlayerHandle {
  player: Artplayer;
}
interface Props {
  source: Source | null;
  settings: PlayerSettings;
  messages: DanmakuMessage[];
  locked: boolean;
  fit: string;
  qualities: Quality[];
  sources: Source[];
  onQuality: (quality: Quality) => void;
  onLine: (source: Source) => void;
  onSettings: (settings: Partial<PlayerSettings>) => void;
  onReady: (handle: PlayerHandle | null) => void;
  onState: (status: string) => void;
  onFailure: (message: string) => void;
  onConfirmed: (source: Source) => void;
}
export function PlayerSurface(props: Props) {
  const host = useRef<HTMLDivElement>(null);
  const player = useRef<Artplayer | null>(null);
  const renderer = useRef<DanmakuRenderer | null>(null);
  const latest = useRef(props);
  latest.current = props;
  const load = useRef<(source: Source) => void>(() => {});
  const stop = useRef<() => void>(() => {});
  const seen = useRef(0);
  const emitted = useRef(0);
  useEffect(() => {
    if (!host.current) return;
    const emitter = document.createElement("div");
    emitter.hidden = true;
    const art = new Artplayer({
      container: host.current,
      url: "",
      isLive: true,
      lang: "zh-cn",
      autoplay: false,
      muted: false,
      volume: 0.8,
      fullscreen: true,
      fullscreenWeb: true,
      pip: true,
      hotkey: false,
      setting: true,
      aspectRatio: true,
      gesture: false,
      fastForward: false,
      autoOrientation: false,
      playsInline: true,
      theme: "#3284d9",
      plugins: [
        danmuku({
          danmuku: [],
          emitter: false,
          mount: emitter,
          antiOverlap: true,
          synchronousPlayback: false,
        }),
      ],
    });
    player.current = art;
    renderer.current = art.plugins.artplayerPluginDanmuku as DanmakuRenderer;
    const session = createStreamSession(art.video, {
      sources: () => latest.current.sources,
      state: (text) => latest.current.onState(text),
      confirmed: (source) => latest.current.onConfirmed(source),
      failure: (text) => latest.current.onFailure(text),
      clearDanmaku: () => {
        void renderer.current?.load();
        emitted.current = 0;
      },
    });
    load.current = session.load;
    stop.current = session.stop;
    const keys = (event: KeyboardEvent) => {
      if (
        latest.current.locked ||
        event.ctrlKey || event.metaKey || event.altKey ||
        /INPUT|TEXTAREA|SELECT|BUTTON|A/.test(
          (event.target as HTMLElement)?.tagName ?? "",
        ) ||
        (event.target as HTMLElement)?.isContentEditable
      )
        return;
      if (event.code === "Space") {
        event.preventDefault();
        art.toggle();
      }
      if (event.code === "KeyF") art.fullscreen = !art.fullscreen;
      if (event.code === "KeyM") art.muted = !art.muted;
    };
    document.addEventListener("keydown", keys);
    const visibility = () => {
      if (document.hidden) {
        void renderer.current?.load();
        emitted.current = 0;
      }
    };
    document.addEventListener("visibilitychange", visibility);
    const intercept = (event: Event) => {
      if (latest.current.locked) {
        event.preventDefault();
        event.stopImmediatePropagation();
      }
    };
    const blockedEvents = [
      "click",
      "dblclick",
      "pointerdown",
      "contextmenu",
      "keydown",
    ];
    for (const name of blockedEvents)
      host.current.addEventListener(name, intercept, true);
    const container = host.current;
    latest.current.onReady({ player: art });
    return () => {
      session.destroy();
      for (const name of blockedEvents)
        container.removeEventListener(name, intercept, true);
      document.removeEventListener("keydown", keys);
      document.removeEventListener("visibilitychange", visibility);
      renderer.current = null;
      player.current = null;
      latest.current.onReady(null);
      art.destroy(false);
    };
  }, []);
  useEffect(() => {
    if (props.source) load.current(props.source);
    else stop.current();
  }, [props.source]);
  useEffect(() => {
    const plugin = renderer.current,
      settings = props.settings;
    if (!plugin) return;
    const configure = () =>
      plugin.config({
        danmuku: [],
        emitter: false,
        opacity: settings.opacity,
        fontSize: settings.size,
        speed: settings.duration,
        margin: [
          settings.top,
          Math.max(
            settings.bottom,
            (host.current?.clientHeight ?? 400) * (1 - settings.area),
          ),
        ],
        antiOverlap: true,
      });
    configure();
    const observer = new ResizeObserver(configure);
    if (host.current) observer.observe(host.current);
    if (settings.enabled) plugin.show();
    else plugin.hide();
    return () => observer.disconnect();
  }, [props.settings]);
  useEffect(() => {
    const plugin = renderer.current;
    if (!plugin) return;
    for (const message of props.messages) {
      if ((message.id ?? 0) <= seen.current) continue;
      seen.current = message.id ?? seen.current;
      if (
        !props.settings.enabled ||
        document.hidden ||
        player.current?.video.paused
      )
        continue;
      if (++emitted.current > 500) {
        void plugin.load();
        emitted.current = 1;
      }
      plugin.emit({
        text: message.message,
        mode: 0,
        color: /^#[0-9a-f]{6}$/i.test(message.color) ? message.color : "#fff",
        style: {
          fontWeight: String(props.settings.weight * 100),
          marginBottom: `${props.settings.bottom}px`,
        },
      });
    }
  }, [props.messages, props.settings]);
  useEffect(() => {
    const art = player.current;
    if (!art) return;
    art.aspectRatio =
      props.fit === "16:9" || props.fit === "4:3" ? props.fit : "default";
    art.video.style.objectFit =
      props.fit === "stretch"
        ? "fill"
        : props.fit === "cover"
          ? "cover"
          : "contain";
  }, [props.fit, props.locked]);
  useEffect(() => {
    const art = player.current;
    if (!art) return;
    // Elements carry platform labels as text, never as HTML.
    const label = (text: string) => {
      const span = document.createElement("span");
      span.textContent = text;
      return span;
    };
    for (const name of [
      "live-quality",
      "live-line",
      "live-danmaku",
      "live-opacity",
      "live-size",
    ]) {
      if (art.setting.find(name)) art.setting.remove(name);
    }
    if (props.qualities.length)
      art.setting.add({
        name: "live-quality",
        html: "清晰度",
        selector: props.qualities.map((item) => ({
          html: label(item.quality),
          value: item.index,
        })),
        onSelect: (item) => {
          const next = latest.current.qualities.find(
            (value) => value.index === item.value,
          );
          if (next) latest.current.onQuality(next);
        },
      });
    if (props.sources.length)
      art.setting.add({
        name: "live-line",
        html: "线路",
        selector: props.sources.map((item) => ({
          html: `线路 ${item.index + 1} · ${item.format.toUpperCase()}`,
          value: item.index,
        })),
        onSelect: (item) => {
          const next = latest.current.sources.find(
            (value) => value.index === item.value,
          );
          if (next) latest.current.onLine(next);
        },
      });
    art.setting.add({
      name: "live-danmaku",
      html: "显示弹幕",
      switch: props.settings.enabled,
      onSwitch: (item) => {
        latest.current.onSettings({ enabled: !item.switch });
        return !item.switch;
      },
    });
    art.setting.add({
      name: "live-opacity",
      html: "弹幕透明度",
      range: [props.settings.opacity, 0.1, 1, 0.1],
      onRange: (item) => {
        latest.current.onSettings({ opacity: Number(item.range?.[0]) });
      },
    });
    art.setting.add({
      name: "live-size",
      html: "弹幕字号",
      range: [props.settings.size, 8, 48, 1],
      onRange: (item) => {
        latest.current.onSettings({ size: Number(item.range?.[0]) });
      },
    });
  }, [props.qualities, props.sources, props.settings]);
  return (
    <div
      className={`player-surface ${props.locked ? "locked" : ""}`}
      ref={host}
    />
  );
}
