import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { App as AntApp, ConfigProvider, theme as antTheme } from "antd";
import zhCN from "antd/locale/zh_CN";

export const themeColors = [
  { id: "blue", name: "蓝色", color: "#1677ff" },
  { id: "green", name: "绿色", color: "#52c41a" },
  { id: "teal", name: "青色", color: "#13c2c2" },
  { id: "rose", name: "玫红", color: "#eb2f96" },
  { id: "amber", name: "金色", color: "#faad14" },
  { id: "violet", name: "紫色", color: "#722ed1" },
] as const;

function read(key: string, fallback: string) {
  try {
    return localStorage.getItem(key) ?? fallback;
  } catch {
    return fallback;
  }
}
function normalizeColor(value: string) {
  return (
    themeColors.find((item) => item.id === value)?.color ??
    (/^#[0-9a-f]{6}$/i.test(value) ? value : "#1677ff")
  );
}
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
  const [mode, setModeState] = useState(() => {
    const saved = read("simple-live-web.theme", "system");
    return ["system", "light", "dark"].includes(saved) ? saved : "system";
  });
  const [primaryColor, setColor] = useState(() =>
    normalizeColor(read("simple-live-web.theme-color", "blue")),
  );
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
  useEffect(() => {
    try {
      localStorage.setItem("simple-live-web.theme", mode);
      localStorage.setItem("simple-live-web.theme-color", primaryColor);
    } catch {
      // Appearance remains usable when browser storage is unavailable.
    }
  }, [mode, primaryColor]);
  useEffect(() => {
    const changed = (event: StorageEvent) => {
      if (event.key === "simple-live-web.theme-color")
        setColor(normalizeColor(event.newValue ?? "blue"));
      if (
        event.key === "simple-live-web.theme" &&
        ["system", "light", "dark"].includes(event.newValue ?? "")
      )
        setModeState(event.newValue!);
    };
    window.addEventListener("storage", changed);
    return () => window.removeEventListener("storage", changed);
  }, []);
  return (
    <AppearanceContext.Provider
      value={{
        mode,
        setMode: (value) => {
          if (["system", "light", "dark"].includes(value)) setModeState(value);
        },
        primaryColor,
        setPrimaryColor: (value) => setColor(normalizeColor(value)),
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
