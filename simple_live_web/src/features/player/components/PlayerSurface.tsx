import { useEffect, useRef, useState, type RefObject } from "react";
import { createPortal } from "react-dom";
import { theme } from "antd";
import Artplayer from "artplayer";
import { Timer } from "lucide-react";
import danmuku, {
  type Result as DanmakuRenderer,
} from "artplayer-plugin-danmuku";
import type { DanmakuMessage, Source, Quality } from "../../../types/playback";
import type { PlayerSettings } from "../../../stores/playerSettings";
import { createStreamSession } from "../streamSession";
import { watchIdlePlayback } from "../idlePause";
import { normalizeDanmakuColor } from "../../danmaku/color";
import { PlayerControls } from "./PlayerControls";

Artplayer.FULLSCREEN_WEB_IN_BODY = false;

type DanmakuQueueState = "wait" | "ready" | "emit" | "stop";

interface DanmakuQueueItem {
  $state: DanmakuQueueState;
  $lastStartTime: number;
  $restTime: number;
  $ref: HTMLElement | null;
}

interface ManagedDanmakuRenderer extends DanmakuRenderer {
  queue?: DanmakuQueueItem[];
  states?: Partial<Record<DanmakuQueueState, DanmakuQueueItem[]>>;
}

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
  const [idleSeconds, setIdleSeconds] = useState<number | null>(null);
  const renderer = useRef<DanmakuRenderer | null>(null);
  const latest = useRef(props);
  latest.current = props;
  const load = useRef<(source: Source) => void>(() => {});
  const stop = useRef<() => void>(() => {});
  const seen = useRef(0);
  const nextDanmakuCompaction = useRef(600);
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
    nextDanmakuCompaction.current = 600;
    const session = createStreamSession(art.video, {
      sources: () => latest.current.sources,
      state: (text) => latest.current.onState(text),
      confirmed: (source) => latest.current.onConfirmed(source),
      failure: (text) => latest.current.onFailure(text),
    });
    const stopIdleWatch = watchIdlePlayback(
      art.video,
      setIdleSeconds,
      session.pauseForIdle,
    );
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
    return () => {
      stopIdleWatch();
      session.destroy();
      if (art.fullscreenWeb) art.fullscreenWeb = false;
      document.removeEventListener("keydown", keys);
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
    const fontSizeChanged = plugin.option.fontSize !== settings.size;
    if (fontSizeChanged) {
      plugin.option.fontSize = settings.size;
      const height = player.current?.template.$danmuku.clientHeight ?? 0;
      const fontSize = Math.round(
        Math.min(Math.max(settings.size, 12), Math.max(height, 12)),
      );
      player.current?.template.$danmuku
        .querySelectorAll<HTMLElement>('[data-state="emit"], [data-state="stop"]')
        .forEach((item) => {
          item.style.fontSize = `${fontSize}px`;
        });
    }
    const height = player.current?.template.$danmuku.clientHeight ?? 400;
    const bottomMargin = height * (1 - settings.area);
    const topMargin = Math.min(
      settings.topMargin,
      Math.max(0, height - bottomMargin - settings.size * 1.2),
    );
    const configure = () =>
      plugin.config({
        danmuku: [],
        emitter: false,
        opacity: settings.opacity,
        speed: settings.duration,
        margin: [
          topMargin,
          bottomMargin,
        ],
        antiOverlap: settings.antiOverlap,
      });
    const danmakuLayer = player.current?.template.$danmuku;
    danmakuLayer?.style.setProperty(
      "--danmaku-vertical-gap",
      `${settings.verticalGap / 2}px`,
    );
    danmakuLayer?.style.setProperty(
      "--danmaku-horizontal-gap",
      `${settings.horizontalGap / 2}px`,
    );
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
      plugin.emit({
        text: message.message,
        mode: 0,
        color: normalizeDanmakuColor(message.color),
        style: {
          fontWeight: String(props.settings.weight * 100),
        },
      });
      const managed = plugin as ManagedDanmakuRenderer;
      const queue = managed.queue;
      const states = managed.states;
      const waiting = states?.wait;
      if (
        !Array.isArray(queue) ||
        !states ||
        !Array.isArray(waiting) ||
        queue.length < nextDanmakuCompaction.current
      )
        continue;

      const expired = new Set(
        waiting.filter(
          (item) =>
            item.$lastStartTime > 0 &&
            item.$restTime <= 0 &&
            item.$ref === null,
        ),
      );
      if (expired.size) {
        managed.queue = queue.filter((item) => !expired.has(item));
        states.wait = waiting.filter((item) => !expired.has(item));
      }
      nextDanmakuCompaction.current = (managed.queue ?? queue).length + 100;
    }
  }, [props.messages, props.settings]);
  return (
    <>
      <div className="player-surface" ref={host} />
      {controlPlayer && idleSeconds !== null &&
        createPortal(
          <div className="player-idle-countdown" role="timer">
            <Timer size={20} aria-hidden="true" />
            <strong>{idleSeconds}</strong>
            <span>秒后暂停直播</span>
          </div>,
          controlPlayer.template.$player,
        )}
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
