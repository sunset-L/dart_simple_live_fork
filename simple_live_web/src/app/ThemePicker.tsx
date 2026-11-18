import { useEffect, useRef, useState } from "react";
import { Check, Monitor, Moon, Sun } from "lucide-react";

export const themeColors = [
  { id: "blue", name: "蓝色", light: "#3284d9", dark: "#68aaf1" },
  { id: "green", name: "翠绿", light: "#17805a", dark: "#53c69b" },
  { id: "teal", name: "青色", light: "#087d87", dark: "#53c7d0" },
  { id: "rose", name: "玫红", light: "#c33e6c", dark: "#f18bad" },
  { id: "amber", name: "琥珀", light: "#b76512", dark: "#edb261" },
  { id: "violet", name: "紫色", light: "#7e52c6", dark: "#bc9bf1" },
] as const;

type ThemeColor = (typeof themeColors)[number]["id"];

export function ThemePicker({
  theme,
  setTheme,
  color,
  setColor,
}: {
  theme: string;
  setTheme: (value: string) => void;
  color: ThemeColor;
  setColor: (value: ThemeColor) => void;
}) {
  const [open, setOpen] = useState(false);
  const container = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (!open) return;
    const outside = (event: Event) => {
      if (!container.current?.contains(event.target as Node)) setOpen(false);
    };
    const escape = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      setOpen(false);
      trigger.current?.focus();
    };
    container.current
      ?.querySelector<HTMLButtonElement>('button[aria-pressed="true"]')
      ?.focus();
    document.addEventListener("pointerdown", outside);
    document.addEventListener("focusin", outside);
    document.addEventListener("keydown", escape);
    return () => {
      document.removeEventListener("pointerdown", outside);
      document.removeEventListener("focusin", outside);
      document.removeEventListener("keydown", escape);
    };
  }, [open]);

  const ModeIcon = theme === "dark" ? Moon : theme === "light" ? Sun : Monitor;
  return (
    <div className="theme-picker" ref={container}>
      <button
        ref={trigger}
        className="icon-button"
        title="主题与颜色"
        aria-label="主题与颜色"
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-controls={open ? "theme-menu" : undefined}
        onClick={() => setOpen((value) => !value)}
      >
        <ModeIcon size={19} />
      </button>
      {open && (
        <div
          id="theme-menu"
          className="theme-menu"
          role="dialog"
          aria-label="外观设置"
        >
          <span className="theme-menu-label">明暗模式</span>
          <div className="segmented theme-modes" role="group" aria-label="明暗模式">
            {[
              { id: "light", label: "浅色", Icon: Sun },
              { id: "dark", label: "深色", Icon: Moon },
              { id: "system", label: "系统", Icon: Monitor },
            ].map(({ id, label, Icon }) => (
              <button
                key={id}
                aria-label={id === "system" ? "跟随系统" : label}
                title={id === "system" ? "跟随系统" : label}
                aria-pressed={theme === id}
                className={theme === id ? "selected" : ""}
                onClick={() => setTheme(id)}
              >
                <Icon size={15} />
                {label}
              </button>
            ))}
          </div>
          <span className="theme-menu-label">主题色</span>
          <div className="theme-swatches" role="group" aria-label="主题色">
            {themeColors.map((item) => (
              <button
                key={item.id}
                className="theme-swatch"
                style={{ backgroundColor: item.light }}
                title={item.name}
                aria-label={`${item.name}主题色`}
                aria-pressed={color === item.id}
                onClick={() => setColor(item.id)}
              >
                {color === item.id && <Check size={18} />}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
