import type { PlayerSettings as Settings } from "../../../stores/playerSettings";
import { Slider, Switch } from "antd";
export const danmakuFields = [
  ["opacity", "不透明度", 0.1, 1, 0.05],
  ["size", "字号", 8, 48, 1],
  ["weight", "字体粗细", 1, 9, 1],
  ["duration", "滚动时长（秒）", 1, 10, 1],
  ["area", "显示区域", 0.1, 1, 0.1],
] as const;
export function PlayerSettings({
  value,
  onChange,
}: {
  value: Settings;
  onChange: (patch: Partial<Settings>) => void;
}) {
  return (
    <section className="player-settings settings-grid">
      <h3>弹幕设置</h3>
      <div className="danmaku-setting-row">
        <span>显示弹幕</span>
        <Switch
          aria-label="显示弹幕"
          checked={value.enabled}
          onChange={(enabled) => onChange({ enabled })}
        />
      </div>
      <div className="danmaku-setting-row">
        <span>防止弹幕重叠</span>
        <Switch
          aria-label="防止弹幕重叠"
          checked={value.antiOverlap}
          onChange={(antiOverlap) => onChange({ antiOverlap })}
        />
      </div>
      <div className="danmaku-setting-row">
        <span>屏蔽福袋和抽奖</span>
        <Switch
          aria-label="屏蔽福袋和抽奖"
          checked={value.fortune}
          onChange={(fortune) => onChange({ fortune })}
        />
      </div>
      {danmakuFields.map(([key, label, min, max, step]) => (
        <div className="danmaku-slider-row" key={key}>
          <span>
            {label} ·{" "}
            {key === "area" || key === "opacity"
              ? `${Math.round(value[key] * 100)}%`
              : value[key]}
          </span>
          <Slider
            aria-label={label}
            min={min}
            max={max}
            step={step}
            value={value[key]}
            tooltip={{
              formatter: (next) =>
                key === "area" || key === "opacity"
                  ? `${Math.round((next ?? 0) * 100)}%`
                  : next,
              getPopupContainer: (trigger) =>
                trigger.closest<HTMLElement>(".art-video-player") ??
                document.body,
            }}
            onChange={(next) => onChange({ [key]: next })}
          />
        </div>
      ))}
    </section>
  );
}
