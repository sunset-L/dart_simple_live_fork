import React from "react";
import { createRoot } from "react-dom/client";
import { App } from "./app/App";
import { AppearanceProvider } from "./app/AppearanceProvider";
import { initializeLibrary } from "./stores/libraryStorage";
import "./styles/app.css";

const root = createRoot(document.getElementById("root")!);
const app = (
  <React.StrictMode>
    <AppearanceProvider>
      <App />
    </AppearanceProvider>
  </React.StrictMode>
);
if (location.pathname.startsWith("/playback/")) {
  root.render(app);
  void initializeLibrary();
} else {
  root.render(
    <div className="loading" role="status">
      正在读取本地数据
    </div>,
  );
  void initializeLibrary().then(() => root.render(app));
}
