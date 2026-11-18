import type { PlayerSettings as Settings } from "../../../stores/playerSettings";
const fields = [
  ["opacity", "不透明度", 0.1, 1, 0.1],
  ["size", "字号", 8, 48, 1],
  ["weight", "字体粗细", 1, 9, 1],
  ["duration", "滚动时长（秒）", 1, 10, 1],
  ["area", "显示区域", 0.1, 1, 0.1],
  ["top", "顶部边距", 0, 48, 4],
  ["bottom", "底部边距", 0, 48, 4],
] as const;
export function PlayerSettings({
  value,
  onChange,
  fit,
  onFit,
}: {
  value: Settings;
  onChange: (patch: Partial<Settings>) => void;
  fit: string;
  onFit: (value: string) => void;
}) {
  return (
    <section className="player-settings settings-grid">
      <h3>弹幕设置</h3>
      <label>
        显示弹幕
        <input
          type="checkbox"
          checked={value.enabled}
          onChange={(event) => onChange({ enabled: event.target.checked })}
        />
      </label>
      <label>
        屏蔽福袋和抽奖
        <input
          type="checkbox"
          checked={value.fortune}
          onChange={(event) => onChange({ fortune: event.target.checked })}
        />
      </label>
      <div className="danmaku-color-setting">
        <span>弹幕颜色</span>
        <div className="segmented" role="group" aria-label="弹幕颜色">
          {[
            ["original", "原色"],
            ["white", "白色"],
            ["custom", "自定义"],
          ].map(([id, label]) => (
            <button
              key={id}
              className={value.colorMode === id ? "selected" : ""}
              aria-pressed={value.colorMode === id}
              onClick={() => onChange({ colorMode: id })}
            >
              {label}
            </button>
          ))}
        </div>
        {value.colorMode === "custom" && (
          <input
            type="color"
            title="自定义弹幕颜色"
            aria-label="自定义弹幕颜色"
            value={value.customColor}
            onChange={(event) => onChange({ customColor: event.target.value })}
          />
        )}
      </div>
      {fields.map(([key, label, min, max, step]) => (
        <label key={key}>
          <span>
            {label} · {value[key]}
          </span>
          <input
            type="range"
            min={min}
            max={max}
            step={step}
            value={value[key]}
            onChange={(event) =>
              onChange({ [key]: Number(event.target.value) })
            }
          />
        </label>
      ))}
      <label>
        画面尺寸
        <select value={fit} onChange={(event) => onFit(event.target.value)}>
          {[
            ["contain", "适应"],
            ["cover", "铺满"],
            ["stretch", "拉伸"],
            ["16:9", "16:9"],
            ["4:3", "4:3"],
          ].map(([id, text]) => (
            <option key={id} value={id}>
              {text}
            </option>
          ))}
        </select>
      </label>
    </section>
  );
}
