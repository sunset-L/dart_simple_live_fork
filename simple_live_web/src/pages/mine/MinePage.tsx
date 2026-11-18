import {
  Cloud,
  ChevronRight,
  History as HistoryIcon,
  Shield,
  Sun,
} from "lucide-react";
import type { Library } from "../../services/libraryData";
import type { Page } from "../../app/routes";
import { Segmented } from "antd";

export function Mine({
  onNavigate,
  data,
  theme,
  setTheme,
}: {
  onNavigate: (page: Page) => void;
  data: Library;
  theme: string;
  setTheme: (value: string) => void;
}) {
  return (
    <div className="mine-content">
      <div className="mine-hero">
        <div className="app-icon">
          <img src="/assets/logo.png" alt="" />
        </div>
        <div>
          <h1>Simple Live</h1>
          <p>Web · v0.1.0</p>
        </div>
      </div>
      <section className="setting-section">
        <h3>数据</h3>
        <button
          className="setting-row link-row"
          onClick={() => onNavigate("sync")}
        >
          <span>
            <Cloud size={19} />
            数据同步
            <small>
              {data.follows.length} 位关注 · {data.histories.length} 条历史
            </small>
          </span>
          <ChevronRight size={17} />
        </button>
        <button
          className="setting-row link-row"
          onClick={() => onNavigate("history")}
        >
          <span>
            <HistoryIcon size={19} />
            历史记录<small>{data.histories.length} 条记录</small>
          </span>
          <ChevronRight size={17} />
        </button>
        <button
          className="setting-row link-row"
          onClick={() => onNavigate("blocked")}
        >
          <span>
            <Shield size={19} />
            弹幕屏蔽词<small>{data.blocked.length} 个词</small>
          </span>
          <ChevronRight size={17} />
        </button>
      </section>
      <section className="setting-section">
        <h3>外观</h3>
        <div className="setting-row">
          <span>
            <Sun size={19} />
            主题
          </span>
          <Segmented
            value={theme}
            onChange={setTheme}
            options={[
              { value: "system", label: "跟随系统" },
              { value: "light", label: "浅色" },
              { value: "dark", label: "深色" },
            ]}
          />
        </div>
      </section>
    </div>
  );
}
