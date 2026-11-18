import { Button, ColorPicker, Popover, Segmented } from "antd";
import { Monitor, Moon, Sun } from "lucide-react";
import { themeColors, useAppearance } from "./AppearanceProvider";

export function ThemePicker() {
  const { mode, setMode, primaryColor, setPrimaryColor } = useAppearance();
  const ModeIcon = mode === "dark" ? Moon : mode === "light" ? Sun : Monitor;
  return (
    <Popover
      trigger="click"
      placement="bottomRight"
      title="外观设置"
      content={
        <div className="theme-menu-content">
          <span className="theme-menu-label">明暗模式</span>
          <Segmented
            block
            value={mode}
            onChange={setMode}
            options={[
              { value: "light", label: "浅色", icon: <Sun size={14} /> },
              { value: "dark", label: "深色", icon: <Moon size={14} /> },
              { value: "system", label: "系统", icon: <Monitor size={14} /> },
            ]}
          />
          <span className="theme-menu-label">主题色</span>
          <ColorPicker
            value={primaryColor}
            onChange={(_, hex) => setPrimaryColor(hex)}
            disabledAlpha
            showText
            presets={[
              {
                label: "主题色",
                colors: themeColors.map((item) => item.color),
              },
            ]}
          />
        </div>
      }
    >
      <Button
        type="text"
        aria-label="主题与颜色"
        title="主题与颜色"
        icon={<ModeIcon size={19} />}
      />
    </Popover>
  );
}
