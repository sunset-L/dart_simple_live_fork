import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { App as AntApp, ConfigProvider, theme as antTheme } from "antd";
import zhCN from "antd/locale/zh_CN";
import {
  normalizeColor,
  updatePreferences,
  usePreferences,
} from "../stores/preferencesStorage";
export { themeColors } from "../stores/preferencesStorage";
const AppearanceContext = createContext({
  mode: "system",
  setMode: (_mode: string) => {},
  primaryColor: "#1677ff",
  setPrimaryColor: (_color: string) => {},
});
export const useAppearance = () => useContext(AppearanceContext);

function TokenBridge({ dark }: { dark: boolean }) {
  const { token } = antTheme.useToken();
  useEffect(() => {
    const root = document.documentElement;
    root.dataset.theme = dark ? "dark" : "light";
    root.style.colorScheme = dark ? "dark" : "light";
    for (const [name, value] of Object.entries({
      bg: token.colorBgLayout,
      surface: token.colorBgContainer,
      "surface-soft": token.colorFillAlter,
      line: token.colorBorderSecondary,
      text: token.colorText,
      muted: token.colorTextSecondary,
      primary: token.colorPrimary,
      "primary-soft": token.colorPrimaryBg,
      danger: token.colorError,
      shadow: token.boxShadowSecondary,
    }))
      root.style.setProperty(`--${name}`, value);
  }, [token, dark]);
  return null;
}

export function AppearanceProvider({ children }: { children: ReactNode }) {
  const { data } = usePreferences();
  const { mode, primaryColor } = data;
  const [systemDark, setSystemDark] = useState(
    () => matchMedia("(prefers-color-scheme: dark)").matches,
  );
  const dark =
    location.pathname.startsWith("/playback/") ||
    (mode === "system" ? systemDark : mode === "dark");
  useEffect(() => {
    const media = matchMedia("(prefers-color-scheme: dark)");
    const changed = () => setSystemDark(media.matches);
    media.addEventListener("change", changed);
    return () => media.removeEventListener("change", changed);
  }, []);
  return (
    <AppearanceContext.Provider
      value={{
        mode,
        setMode: (value) => {
          if (["system", "light", "dark"].includes(value))
            updatePreferences({ mode: value });
        },
        primaryColor,
        setPrimaryColor: (value) =>
          updatePreferences({ primaryColor: normalizeColor(value) }),
      }}
    >
      <ConfigProvider
        locale={zhCN}
        theme={{
          algorithm: dark ? antTheme.darkAlgorithm : antTheme.defaultAlgorithm,
          token: {
            colorPrimary: primaryColor,
            borderRadius: 6,
            fontFamily: '"Segoe UI", "Microsoft YaHei", sans-serif',
            fontSize: 14,
            zIndexPopupBase: 10000,
          },
        }}
      >
        <TokenBridge dark={dark} />
        <AntApp
          component={false}
          message={{
            getContainer: () =>
              (document.fullscreenElement as HTMLElement | null) ??
              document.body,
          }}
        >
          {children}
        </AntApp>
      </ConfigProvider>
    </AppearanceContext.Provider>
  );
}
