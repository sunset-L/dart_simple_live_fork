import { useEffect, useLayoutEffect, useState } from "react";
import { createPortal } from "react-dom";
import {
  Button,
  ConfigProvider,
  Dropdown,
  Modal,
  Popover,
  Tooltip,
} from "antd";
import { ChevronDown, RefreshCw } from "lucide-react";
import type Artplayer from "artplayer";
import danmuku from "artplayer-plugin-danmuku";
import type { Quality, Source } from "../../../types/playback";
import type { PlayerSettings as Settings } from "../../../stores/playerSettings";
import { PlayerSettings } from "./PlayerSettings";
import { PlaybackInfo } from "./PlaybackInfo";

// The plugin exports its original icons at runtime, but omits them from its types.
const danmakuIcons = (
  danmuku as typeof danmuku & {
    icons: Record<"$on" | "$off" | "$config", string>;
  }
).icons;

function DanmakuIcon({ name }: { name: keyof typeof danmakuIcons }) {
  return (
    <span
      className="player-danmaku-icon"
      aria-hidden="true"
      dangerouslySetInnerHTML={{ __html: danmakuIcons[name] }}
    />
  );
}

function PlayerSelect({
  label,
  value,
  options,
  disabled,
  onChange,
  open,
  onOpenChange,
}: {
  label: string;
  value?: number;
  options: { value: number; label: string }[];
  disabled: boolean;
  onChange: (value: number) => void;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const selected = options.find((item) => item.value === value);
  return (
    <Dropdown
      trigger={["hover"]}
      mouseEnterDelay={0.12}
      mouseLeaveDelay={0.15}
      placement="topRight"
      disabled={disabled || !options.length}
      open={open && !disabled && options.length > 0}
      onOpenChange={onOpenChange}
      classNames={{ root: "player-control-popup" }}
      menu={{
        selectable: true,
        selectedKeys: value === undefined ? [] : [String(value)],
        items: options.map((item) => ({
          key: String(item.value),
          label: item.label,
        })),
        onClick: ({ key }) => {
          if (!disabled) onChange(Number(key));
          onOpenChange(false);
        },
      }}
    >
      <Button
        type="text"
        className="player-control-button player-select-trigger"
        title={`${label}：${selected?.label ?? "暂不可用"}`}
        aria-label={`${label}：${selected?.label ?? "暂不可用"}`}
        aria-haspopup="menu"
        aria-expanded={open}
        disabled={disabled || !options.length}
        onKeyDown={(event) => {
          if (["ArrowDown", "Enter", " "].includes(event.key)) {
            event.preventDefault();
            onOpenChange(true);
          }
          if (event.key === "Escape") onOpenChange(false);
        }}
      >
        <span>{selected?.label ?? label}</span>
        <ChevronDown size={12} />
      </Button>
    </Dropdown>
  );
}

export function PlayerControls({
  player,
  status,
  switching,
  refreshing,
  quality,
  qualities,
  source,
  sources,
  settings,
  onRefresh,
  onQuality,
  onLine,
  onSettings,
}: {
  player: Artplayer;
  status: string;
  switching: boolean;
  refreshing: boolean;
  quality: Quality | null;
  qualities: Quality[];
  source: Source | null;
  sources: Source[];
  settings: Settings;
  onRefresh: () => void;
  onQuality: (quality: Quality) => void;
  onLine: (source: Source) => void;
  onSettings: (settings: Partial<Settings>) => void;
}) {
  const [slots, setSlots] = useState<Record<string, HTMLElement>>({});
  const [openMenu, setOpenMenu] = useState<
    "line" | "quality" | "settings" | null
  >(null);
  const [infoOpen, setInfoOpen] = useState(false);
  useLayoutEffect(() => {
    if (player.isDestroy) return;
    const volume = player.template.$player.querySelector<HTMLElement>(
      ".art-control-volume",
    );
    if (volume) {
      volume.dataset.index = "25";
      player.template.$controlsRight.prepend(volume);
    }
    const controls: Record<string, HTMLElement> = {};
    for (const [name, position, index] of [
      ["refresh", "left", 20],
      ["danmaku", "right", 19],
      ["line", "right", 21],
      ["quality", "right", 22],
    ] as const) {
      // ArtPlayer's runtime add() does not return the node advertised by its types.
      player.controls.add({
        name: `live-${name}`,
        position,
        index,
        html: "",
        style: { padding: "0" },
        mounted: (slot) => {
          controls[name] = slot;
        },
      });
    }
    controls.danmaku.classList.add("live-danmaku-controls");
    setSlots(controls);
    player.contextmenu.update({
      name: "info",
      html: "播放信息",
      index: 5,
      click: () => {
        player.contextmenu.show = false;
        setInfoOpen(true);
      },
    });
    return () => {
      if (!player.isDestroy) {
        for (const name of Object.keys(controls))
          player.controls.remove(`live-${name}`);
        player.contextmenu.remove("info");
      }
    };
  }, [player]);
  useEffect(() => {
    if (player.isDestroy) return;
    const resize = () => {
      player.template.$player.style.setProperty(
        "--live-menu-height",
        `${Math.max(32, player.template.$player.clientHeight - 64)}px`,
      );
    };
    const observer = new ResizeObserver(resize);
    observer.observe(player.template.$player);
    resize();
    return () => observer.disconnect();
  }, [player]);
  useEffect(() => {
    if (player.isDestroy) return;
    const root = player.template.$player;
    const toolbar = player.template.$bottom;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let windowFocused = document.hasFocus();
    const interacting = () =>
      windowFocused &&
      Boolean(
        openMenu ||
        toolbar.matches(":hover") ||
        (toolbar.contains(document.activeElement) &&
          document.activeElement?.matches(":focus-visible")),
      );
    const hideLater = () => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        if (!player.isDestroy && !interacting()) player.controls.show = false;
      }, 3000);
    };
    const show = () => {
      player.controls.show = true;
    };
    const blurred = () => {
      windowFocused = false;
      hideLater();
    };
    const focused = () => {
      windowFocused = true;
      show();
    };
    const changed = (visible: boolean) => {
      if (!visible && interacting()) {
        player.controls.show = true;
        return;
      }
      root.classList.toggle("live-controls-open", visible && Boolean(openMenu));
      if (visible) hideLater();
    };
    root.addEventListener("pointermove", show);
    root.addEventListener("pointerleave", hideLater);
    root.addEventListener("focusin", show);
    root.addEventListener("focusout", hideLater);
    toolbar.addEventListener("pointerenter", show);
    toolbar.addEventListener("pointerleave", hideLater);
    window.addEventListener("blur", blurred);
    window.addEventListener("focus", focused);
    player.on("control", changed);
    show();
    return () => {
      clearTimeout(timer);
      root.removeEventListener("pointermove", show);
      root.removeEventListener("pointerleave", hideLater);
      root.removeEventListener("focusin", show);
      root.removeEventListener("focusout", hideLater);
      toolbar.removeEventListener("pointerenter", show);
      toolbar.removeEventListener("pointerleave", hideLater);
      window.removeEventListener("blur", blurred);
      window.removeEventListener("focus", focused);
      player.off("control", changed);
      player.template.$player.classList.remove("live-controls-open");
    };
  }, [openMenu, player]);
  useEffect(() => {
    if (switching || refreshing) setOpenMenu(null);
  }, [switching, refreshing]);
  if (player.isDestroy) return null;
  return (
    <ConfigProvider getPopupContainer={() => player.template.$player}>
      {slots.refresh &&
        createPortal(
          <Tooltip title="刷新取流" placement="top">
            <Button
              type="text"
              className="player-control-button"
              aria-label="刷新取流"
              disabled={refreshing}
              icon={
                <RefreshCw size={20} className={refreshing ? "spin" : ""} />
              }
              onClick={onRefresh}
            />
          </Tooltip>,
          slots.refresh,
        )}
      {slots.line &&
        createPortal(
          <PlayerSelect
            label="线路"
            value={source?.index}
            options={sources.map((item) => ({
              value: item.index,
              label: `线路 ${item.index + 1}`,
            }))}
            disabled={switching || refreshing}
            open={openMenu === "line"}
            onOpenChange={(open) => setOpenMenu(open ? "line" : null)}
            onChange={(value) => {
              const next = sources.find((item) => item.index === value);
              if (next) onLine(next);
            }}
          />,
          slots.line,
        )}
      {slots.quality &&
        createPortal(
          <PlayerSelect
            label="清晰度"
            value={quality?.index}
            options={qualities.map((item) => ({
              value: item.index,
              label: item.quality,
            }))}
            disabled={switching || refreshing}
            open={openMenu === "quality"}
            onOpenChange={(open) => setOpenMenu(open ? "quality" : null)}
            onChange={(value) => {
              const next = qualities.find((item) => item.index === value);
              if (next) onQuality(next);
            }}
          />,
          slots.quality,
        )}
      {slots.danmaku &&
        createPortal(
          <>
            <Tooltip title={settings.enabled ? "隐藏弹幕" : "显示弹幕"}>
              <Button
                type="text"
                className="player-control-button"
                aria-label={settings.enabled ? "隐藏弹幕" : "显示弹幕"}
                aria-pressed={settings.enabled}
                icon={<DanmakuIcon name={settings.enabled ? "$on" : "$off"} />}
                onClick={() => onSettings({ enabled: !settings.enabled })}
              />
            </Tooltip>
            <Popover
              trigger="click"
              placement="topRight"
              title="弹幕设置"
              open={openMenu === "settings"}
              onOpenChange={(open) => setOpenMenu(open ? "settings" : null)}
              classNames={{ root: "player-settings-popup" }}
              content={
                <PlayerSettings value={settings} onChange={onSettings} />
              }
            >
              <Button
                type="text"
                className="player-control-button"
                title="弹幕设置"
                aria-label="弹幕设置"
                aria-expanded={openMenu === "settings"}
                icon={<DanmakuIcon name="$config" />}
              />
            </Popover>
          </>,
          slots.danmaku,
        )}
      <Modal
        title="播放信息"
        open={infoOpen}
        onCancel={() => setInfoOpen(false)}
        footer={null}
        getContainer={() => player.template.$player}
        centered
        width={460}
        destroyOnHidden
      >
        {infoOpen && <PlaybackInfo player={player} status={status} />}
      </Modal>
    </ConfigProvider>
  );
}
