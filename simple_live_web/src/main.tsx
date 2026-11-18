import React from "react";
import { createRoot } from "react-dom/client";
import { App } from "./app/App";
import { initializeLibrary } from "./stores/libraryStorage";
import "./styles/app.css";

const root = createRoot(document.getElementById("root")!);
root.render(<div className="loading" role="status">正在读取本地数据</div>);
void initializeLibrary().then(() =>
  root.render(
    <React.StrictMode>
      <App />
    </React.StrictMode>,
  ),
);
