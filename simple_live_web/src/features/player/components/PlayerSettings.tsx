import type { PlayerSettings as Settings } from "../../../stores/playerSettings";
import { Slider, Switch } from "antd";
export const danmakuFields = [
  {
    key: "opacity",
    label: "不透明度",
    min: 0.1,
    max: 1,
    step: 0.05,
    unit: "%",
  },
  { key: "size", label: "字号", min: 8, max: 48, step: 1, unit: "px" },
  { key: "weight", label: "字体粗细", min: 1, max: 9, step: 1, unit: "" },
  { key: "duration", label: "滚动时长", min: 1, max: 10, step: 1, unit: "秒" },
  { key: "area", label: "显示区域", min: 0.1, max: 1, step: 0.1, unit: "%" },
  { key: "topMargin", label: "顶部间距", min: 0, max: 48, step: 4, unit: "px" },
  {
    key: "verticalGap",
    label: "弹幕纵向间距",
    min: 0,
    max: 40,
    step: 2,
    unit: "px",
  },
  {
    key: "horizontalGap",
    label: "弹幕横向间距",
    min: 0,
    max: 100,
    step: 4,
    unit: "px",
  },
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
      {danmakuFields.map(({ key, label, min, max, step, unit }) => (
        <div className="danmaku-slider-row" key={key}>
          <span>
            {label} ·{" "}
            {unit === "%"
              ? `${Math.round(value[key] * 100)}%`
              : `${value[key]}${unit}`}
          </span>
          <Slider
            aria-label={label}
            min={min}
            max={max}
            step={step}
            value={value[key]}
            tooltip={{
              formatter: (next) =>
                unit === "%"
                  ? `${Math.round((next ?? 0) * 100)}%`
                  : `${next ?? value[key]}${unit}`,
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
