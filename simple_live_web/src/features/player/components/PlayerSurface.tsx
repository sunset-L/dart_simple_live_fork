import { useEffect, useRef, useState, type RefObject } from "react";
import { theme } from "antd";
import Artplayer from "artplayer";
import danmuku, {
  type Result as DanmakuRenderer,
} from "artplayer-plugin-danmuku";
import type { DanmakuMessage, Source, Quality } from "../../../types/playback";
import type { PlayerSettings } from "../../../stores/playerSettings";
import { createStreamSession } from "../streamSession";
import { normalizeDanmakuColor } from "../../danmaku/color";
import { PlayerControls } from "./PlayerControls";

Artplayer.FULLSCREEN_WEB_IN_BODY = false;

interface Props {
  danmakuContainer: RefObject<HTMLDivElement | null>;
  source: Source | null;
  loading: boolean;
  refreshing: boolean;
  switching: boolean;
  settings: PlayerSettings;
  messages: DanmakuMessage[];
  status: string;
  qualities: Quality[];
  quality: Quality | null;
  sources: Source[];
  onQuality: (quality: Quality) => void;
  onLine: (source: Source) => void;
  onRefresh: () => void;
  onSettings: (settings: Partial<PlayerSettings>) => void;
  onState: (status: string) => void;
  onFailure: (message: string) => void;
  onConfirmed: (source: Source) => void;
}
export function PlayerSurface(props: Props) {
  const host = useRef<HTMLDivElement>(null);
  const player = useRef<Artplayer | null>(null);
  const [controlPlayer, setControlPlayer] = useState<Artplayer | null>(null);
  const renderer = useRef<DanmakuRenderer | null>(null);
  const latest = useRef(props);
  latest.current = props;
  const load = useRef<(source: Source) => void>(() => {});
  const stop = useRef<() => void>(() => {});
  const seen = useRef(0);
  const emitted = useRef(0);
  const { token } = theme.useToken();
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
      setting: false,
      aspectRatio: true,
      gesture: false,
      fastForward: false,
      autoOrientation: false,
      playsInline: true,
      theme:
        getComputedStyle(host.current).getPropertyValue("--primary").trim() ||
        "#1677ff",
      plugins: [
        (art) => {
          const layer = art.template.$danmuku;
          layer.classList.add("stage-danmaku");
          (
            latest.current.danmakuContainer.current ?? art.template.$player
          ).append(layer);
          // Let the renderer measure its own layer while ArtPlayer keeps its video frame.
          const template = new Proxy(art.template, {
            get: (target, key) =>
              key === "$player" ? layer : Reflect.get(target, key, target),
          });
          const renderingPlayer = new Proxy(art, {
            get: (target, key) => {
              if (key === "template") return template;
              const value = Reflect.get(target, key, target);
              return typeof value === "function" && key !== "constructor"
                ? value.bind(target)
                : value;
            },
          });
          return danmuku({
            danmuku: [],
            emitter: false,
            mount: emitter,
            antiOverlap: true,
            synchronousPlayback: false,
          })(renderingPlayer);
        },
      ],
    });
    const layer = art.template.$danmuku;
    const positionDanmaku = () => {
      const container =
        art.fullscreen || art.fullscreenWeb
          ? art.template.$player
          : (latest.current.danmakuContainer.current ?? art.template.$player);
      if (layer.parentElement !== container) container.append(layer);
    };
    art.on("fullscreen", positionDanmaku);
    art.on("fullscreenWeb", positionDanmaku);
    positionDanmaku();
    player.current = art;
    setControlPlayer(art);
    art.loading.show = latest.current.loading;
    // Suppress the library's click-to-pause and double-click native fullscreen.
    art.proxy(
      art.video,
      "click",
      (event) => {
        event.stopImmediatePropagation();
        art.controls.show = true;
      },
      true,
    );
    art.proxy(
      art.video,
      "dblclick",
      (event) => {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (!art.fullscreen) art.fullscreenWeb = !art.fullscreenWeb;
      },
      true,
    );
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
        event.ctrlKey ||
        event.metaKey ||
        event.altKey ||
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
      if (event.code === "KeyF" && !art.fullscreen)
        art.fullscreenWeb = !art.fullscreenWeb;
      if (event.code === "Escape" && art.fullscreenWeb)
        art.fullscreenWeb = false;
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
    return () => {
      session.destroy();
      if (art.fullscreenWeb) art.fullscreenWeb = false;
      document.removeEventListener("keydown", keys);
      document.removeEventListener("visibilitychange", visibility);
      renderer.current = null;
      player.current = null;
      art.off("fullscreen", positionDanmaku);
      art.off("fullscreenWeb", positionDanmaku);
      art.destroy(false);
      layer.remove();
    };
  }, []);
  useEffect(() => {
    if (player.current && !player.current.isDestroy)
      player.current.theme = token.colorPrimary;
  }, [token.colorPrimary, controlPlayer]);
  useEffect(() => {
    if (props.source) load.current(props.source);
    else stop.current();
  }, [props.source]);
  useEffect(() => {
    if (!props.source && player.current)
      player.current.loading.show = props.loading;
  }, [props.loading, props.source]);
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
          0,
          (player.current?.template.$danmuku.clientHeight ?? 400) *
            (1 - settings.area),
        ],
        antiOverlap: settings.antiOverlap,
      });
    configure();
    const observer = new ResizeObserver(() => {
      configure();
      player.current?.emit("resize");
    });
    if (player.current) observer.observe(player.current.template.$danmuku);
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
        color: normalizeDanmakuColor(message.color),
        style: {
          fontWeight: String(props.settings.weight * 100),
        },
      });
    }
  }, [props.messages, props.settings]);
  return (
    <>
      <div className="player-surface" ref={host} />
      {controlPlayer && (
        <PlayerControls
          key={controlPlayer.id}
          player={controlPlayer}
          status={props.status}
          switching={props.switching}
          refreshing={props.refreshing}
          quality={props.quality}
          qualities={props.qualities}
          source={props.source}
          sources={props.sources}
          settings={props.settings}
          onRefresh={props.onRefresh}
          onQuality={props.onQuality}
          onLine={props.onLine}
          onSettings={props.onSettings}
        />
      )}
    </>
  );
}
