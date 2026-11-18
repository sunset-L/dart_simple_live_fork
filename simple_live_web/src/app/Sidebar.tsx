import { useState } from "react";
import {
  ChevronLeft,
  ChevronRight,
  Cloud,
  Compass,
  Grid2X2,
  Heart,
  User,
} from "lucide-react";
import type { Page } from "./routes";

const navigation = [
  { id: "home", label: "首页", icon: Compass },
  { id: "follow", label: "关注", icon: Heart },
  { id: "category", label: "分类", icon: Grid2X2 },
  { id: "mine", label: "我的", icon: User },
] as const;

export function Sidebar({
  activePage,
  onNavigate,
}: {
  activePage: Page;
  onNavigate: (page: Page) => void;
}) {
  const [collapsed, setCollapsed] = useState(() => {
    try {
      return localStorage.getItem("simple-live-web.sidebar-collapsed") === "1";
    } catch {
      return false;
    }
  });
  function toggle() {
    const next = !collapsed;
    setCollapsed(next);
    try {
      localStorage.setItem("simple-live-web.sidebar-collapsed", next ? "1" : "0");
    } catch {
      /* Navigation remains usable without browser storage. */
    }
  }
  return (
    <aside className={`sidebar ${collapsed ? "is-collapsed" : ""}`}>
      <div className="sidebar-header">
        <div className="brand">
          <img src="/assets/logo.png" alt="Simple Live" />
          <strong>Simple Live</strong>
          <span>WEB</span>
        </div>
      </div>
      <button
        className="sidebar-toggle"
        title={collapsed ? "展开导航" : "收起导航"}
        aria-label={collapsed ? "展开导航" : "收起导航"}
        aria-expanded={!collapsed}
        aria-controls="main-navigation"
        onClick={toggle}
      >
        {collapsed ? <ChevronRight size={17} /> : <ChevronLeft size={17} />}
      </button>
      <nav id="main-navigation" aria-label="主导航">
        {navigation.map((item) => {
          const Icon = item.icon;
          return (
            <button
              key={item.id}
              title={item.label}
              aria-label={item.label}
              aria-current={activePage === item.id ? "page" : undefined}
              className={activePage === item.id ? "active" : ""}
              onClick={() => onNavigate(item.id)}
            >
              <Icon size={20} />
              <span className="nav-label">{item.label}</span>
            </button>
          );
        })}
      </nav>
      <div className="sidebar-foot">
        <button
          title="数据同步"
          aria-label="数据同步"
          onClick={() => onNavigate("sync")}
        >
          <Cloud size={19} />
          <span className="nav-label">数据同步</span>
        </button>
        <button
          className="profile-mini"
          title="本地数据"
          aria-label="本地数据"
          onClick={() => onNavigate("mine")}
        >
          <span className="avatar">
            <User size={15} />
          </span>
          <span className="nav-label">本地数据</span>
          <ChevronRight className="nav-label" size={16} />
        </button>
      </div>
    </aside>
  );
}
