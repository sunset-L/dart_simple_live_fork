import { useState } from "react";
export const defaults = {
  enabled: true,
  opacity: 0.9,
  size: 20,
  weight: 4,
  duration: 8,
  area: 0.8,
  top: 0,
  bottom: 0,
  fortune: false,
};
export type PlayerSettings = typeof defaults;
const key = "simple-live-web.player.v1";
export function usePlayerSettings() {
  const [settings, setSettings] = useState<PlayerSettings>(() => {
    try {
      const value = JSON.parse(localStorage.getItem(key) ?? "{}");
      const result = { ...defaults };
      for (const field of Object.keys(defaults) as (keyof PlayerSettings)[]) {
        if (typeof value[field] === typeof defaults[field])
          Object.assign(result, { [field]: value[field] });
      }
      const limits = {
        opacity: [0.1, 1],
        size: [8, 48],
        weight: [1, 9],
        duration: [1, 10],
        area: [0.1, 1],
        top: [0, 48],
        bottom: [0, 48],
      } as const;
      for (const field of Object.keys(limits) as (keyof typeof limits)[]) {
        const [min, max] = limits[field];
        result[field] = Number.isFinite(result[field])
          ? Math.min(max, Math.max(min, result[field]))
          : defaults[field];
      }
      return result;
    } catch {
      return defaults;
    }
  });
  return [
    settings,
    (patch: Partial<PlayerSettings>) =>
      setSettings((previous) => {
        const next = { ...previous, ...patch };
        try {
          localStorage.setItem(key, JSON.stringify(next));
        } catch {
          /* Keep current session usable when storage is full. */
        }
        return next;
      }),
  ] as const;
}
