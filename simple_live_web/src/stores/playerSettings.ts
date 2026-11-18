import {
  updatePreferences,
  usePreferences,
  type PlayerSettings,
} from "./preferencesStorage";
export { playerDefaults as defaults } from "./preferencesStorage";
export type { PlayerSettings } from "./preferencesStorage";
export function usePlayerSettings() {
  const { data } = usePreferences();
  return [
    data.player,
    (patch: Partial<PlayerSettings>) =>
      updatePreferences({ player: patch }),
  ] as const;
}
