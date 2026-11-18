import React from "react";
import { createRoot } from "react-dom/client";
import { App } from "./app/App";
import { AppearanceProvider } from "./app/AppearanceProvider";
import { initializeLibrary } from "./stores/libraryStorage";
import { initializePreferences } from "./stores/preferencesStorage";
import "./styles/app.css";

const legacyRoom = location.pathname.match(
  /^\/playback\/(bilibili|douyu|huya|douyin)\/([A-Za-z0-9_-]{1,100})$/,
);
if (legacyRoom)
  history.replaceState(
    history.state,
    "",
    `/live/${legacyRoom[1]}/${legacyRoom[2]}${location.search}${location.hash}`,
  );

const root = createRoot(document.getElementById("root")!);
const app = (
  <React.StrictMode>
    <AppearanceProvider>
      <App />
    </AppearanceProvider>
  </React.StrictMode>
);
if (location.pathname.startsWith("/live/")) {
  root.render(app);
  void initializeLibrary();
  void initializePreferences();
} else {
  root.render(
    <div className="loading" role="status">
      正在读取本地数据
    </div>,
  );
  void Promise.all([initializeLibrary(), initializePreferences()]).then(() =>
    root.render(app),
  );
}
