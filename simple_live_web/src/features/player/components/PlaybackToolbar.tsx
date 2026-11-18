import {
  Info,
  Lock,
  MessageCircle,
  RefreshCw,
  Settings2,
  Unlock,
} from "lucide-react";
import type { Quality, Source } from "../../../types/playback";

interface Props {
  locked: boolean;
  onLock: () => void;
  onRefresh: () => void;
  danmaku: boolean;
  onDanmaku: () => void;
  switching: boolean;
  qualities: Quality[];
  quality: Quality | null;
  sources: Source[];
  source: Source | null;
  onQuality: (quality: Quality) => void;
  onLine: (source: Source) => void;
  onPanel: (panel: string) => void;
}

export function PlaybackToolbar(props: Props) {
  return (
    <div className="player-toolbar">
      <button
        title={props.locked ? "解锁" : "锁定"}
        aria-label={props.locked ? "解锁" : "锁定"}
        onClick={props.onLock}
      >
        {props.locked ? <Unlock size={18} /> : <Lock size={18} />}
      </button>
      <button
        disabled={props.locked}
        title="刷新取流"
        aria-label="刷新取流"
        onClick={props.onRefresh}
      >
        <RefreshCw size={18} />
      </button>
      <button
        disabled={props.locked}
        title="弹幕开关"
        aria-label="弹幕开关"
        aria-pressed={props.danmaku}
        onClick={props.onDanmaku}
      >
        <MessageCircle size={18} />
      </button>
      <select
        disabled={props.locked || props.switching || !props.qualities.length}
        aria-label="清晰度"
        value={props.quality?.index ?? ""}
        onChange={(event) => {
          const next = props.qualities.find(
            (item) => item.index === Number(event.target.value),
          );
          if (next) props.onQuality(next);
        }}
      >
        <option value="" disabled>
          清晰度
        </option>
        {props.qualities.map((item) => (
          <option key={item.index} value={item.index}>
            {item.quality}
          </option>
        ))}
      </select>
      <select
        disabled={props.locked || props.switching || !props.sources.length}
        aria-label="播放线路"
        value={props.source?.index ?? ""}
        onChange={(event) => {
          const next = props.sources.find(
            (item) => item.index === Number(event.target.value),
          );
          if (next) props.onLine(next);
        }}
      >
        <option value="" disabled>
          播放线路
        </option>
        {props.sources.map((item) => (
          <option key={item.index} value={item.index}>
            线路 {item.index + 1} · {item.format.toUpperCase()}
          </option>
        ))}
      </select>
      <button
        disabled={props.locked}
        title="设置"
        aria-label="设置"
        onClick={() => props.onPanel("settings")}
      >
        <Settings2 size={18} />
      </button>
      <button
        disabled={props.locked}
        title="播放信息"
        aria-label="播放信息"
        onClick={() => props.onPanel("info")}
      >
        <Info size={18} />
      </button>
    </div>
  );
}
