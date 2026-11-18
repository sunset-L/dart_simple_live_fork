import { lazy, Suspense, useEffect, useRef, useState } from "react";
import {
  ArrowLeft,
  ChevronRight,
  Cloud,
  Compass,
  Download,
  Grid2X2,
  Heart,
  Monitor,
  Moon,
  Search,
  Sun,
  Trash2,
  User,
  X,
} from "lucide-react";
import { Catalog } from "../features/catalog/Catalog";
import { Sync } from "../features/sync/Sync";
import { FollowPage } from "../pages/follow/FollowPage";
import { Mine } from "../pages/mine/MinePage";
import { HistoryPage } from "../pages/history/HistoryPage";
import { Blocked } from "../pages/blocked/BlockedPage";
import { TagDialog } from "../features/follow/TagDialog";
import { AddFollow } from "../features/follow/AddFollow";
import { openPlayback } from "./routes";
const PlaybackPage = lazy(() =>
  import("../pages/playback/PlaybackPage").then((module) => ({
    default: module.PlaybackPage,
  })),
);
import {
  download,
  emptyLibrary,
  loadLibrary,
  rawLibrary,
  resetLibrary,
  saveLibrary,
  type Follow,
  type History,
  type Library,
  type Room,
} from "../services/libraryData";

type Page =
  "home" | "follow" | "category" | "mine" | "sync" | "history" | "blocked";
const navigation = [
  { id: "home", label: "首页", icon: Compass },
  { id: "follow", label: "关注", icon: Heart },
  { id: "category", label: "分类", icon: Grid2X2 },
  { id: "mine", label: "我的", icon: User },
] as const;
const pageNames: Record<Page, string> = {
  home: "首页",
  follow: "我的关注",
  category: "全部分类",
  mine: "我的",
  sync: "数据同步",
  history: "历史记录",
  blocked: "弹幕屏蔽词",
};
const validPage = (): Page => {
  const value = location.hash.slice(1);
  return Object.hasOwn(pageNames, value) ? (value as Page) : "home";
};
const initial = loadLibrary();

export function App() {
  const [page, setPage] = useState<Page>(validPage);
  const playbackMatch = location.pathname.match(
    /^\/playback\/(bilibili|douyu|huya|douyin)\/([A-Za-z0-9_-]{1,100})$/,
  );
  const [site, setSite] = useState("bilibili");
  const [data, setData] = useState(initial.data);
  const [storageError, setStorageError] = useState(initial.error);
  const [query, setQuery] = useState("");
  const [search, setSearch] = useState("");
  const [toast, setToast] = useState("");
  const [editing, setEditing] = useState<Follow | null>(null);
  const [addFollow, setAddFollow] = useState(false);
  const [tag, setTag] = useState("全部");
  const [filter, setFilter] = useState("all");
  const [theme, setTheme] = useState(() => {
    try {
      return localStorage.getItem("simple-live-web.theme") ?? "system";
    } catch {
      return "system";
    }
  });
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const library = useRef(data);
  library.current = data;

  useEffect(() => {
    const onHash = () => {
      setPage(validPage());
      setSearch("");
      setQuery("");
    };
    window.addEventListener("hashchange", onHash);
    return () => window.removeEventListener("hashchange", onHash);
  }, []);
  useEffect(() => {
    const media = matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      document.documentElement.dataset.theme =
        theme === "system" ? (media.matches ? "dark" : "light") : theme;
    };
    apply();
    media.addEventListener("change", apply);
    try {
      localStorage.setItem("simple-live-web.theme", theme);
    } catch {
      /* Appearance still works without persistence. */
    }
    return () => media.removeEventListener("change", apply);
  }, [theme]);
  useEffect(() => {
    const onStorage = (event: StorageEvent) => {
      if (event.key !== "simple-live-web.library.v1" && event.key !== null)
        return;
      const loaded = loadLibrary();
      library.current = loaded.data;
      setData(loaded.data);
      setStorageError(loaded.error);
    };
    window.addEventListener("storage", onStorage);
    return () => {
      window.removeEventListener("storage", onStorage);
      clearTimeout(timer.current);
    };
  }, []);

  function notify(message: string) {
    setToast(message);
    clearTimeout(timer.current);
    timer.current = setTimeout(() => setToast(""), 5500);
  }
  function commit(next: Library, expected?: Library) {
    if (storageError) throw new Error(storageError);
    const current = loadLibrary();
    if (current.error) throw new Error(current.error);
    if (
      JSON.stringify(current.data) !==
      JSON.stringify(expected ?? library.current)
    ) {
      library.current = current.data;
      setData(current.data);
      throw new Error("本地数据已在其他页面更新，请重新执行操作");
    }
    saveLibrary(next);
    library.current = next;
    setData(next);
  }
  function change(action: () => void) {
    try {
      action();
    } catch (error) {
      notify(error instanceof Error ? error.message : "操作失败");
    }
  }
  function go(next: Page) {
    location.hash = next;
  }
  function toggleFollow(room: Room | Follow | History) {
    change(() => {
      const id = `${room.siteId}_${room.roomId}`;
      const current = library.current;
      const exists = current.follows.some((user) => user.id === id);
      commit({
        ...current,
        follows: exists
          ? current.follows.filter((user) => user.id !== id)
          : [
              ...current.follows,
              {
                id,
                roomId: room.roomId,
                siteId: room.siteId,
                userName: room.userName,
                face: "face" in room ? room.face : "",
                addTime: new Date().toISOString(),
                tag: "全部",
              },
            ],
        tags: exists
          ? current.tags.map((item) => ({
              ...item,
              userId: item.userId.filter((user) => user !== id),
            }))
          : current.tags,
      });
      notify(exists ? "已取消关注" : "已添加关注");
    });
  }
  function saveTag(name: string) {
    change(() => {
      if (!editing) return;
      const current = library.current;
      if (!current.follows.some((item) => item.id === editing.id))
        throw new Error("此主播已取消关注");
      const tags = current.tags.map((item) => ({
        ...item,
        userId: item.userId.filter((id) => id !== editing.id),
      }));
      if (name !== "全部") {
        const existing = tags.find((item) => item.tag === name);
        if (existing) existing.userId.push(editing.id);
        else
          tags.push({
            id: crypto.randomUUID(),
            tag: name,
            userId: [editing.id],
          });
      }
      commit({
        ...current,
        tags,
        follows: current.follows.map((item) =>
          item.id === editing.id ? { ...item, tag: name } : item,
        ),
      });
      setEditing(null);
    });
  }
  const isCatalog = page === "home" || page === "category";
  const secondary = ["sync", "history", "blocked"].includes(page);
  const activeNav = secondary ? "mine" : page;
  const following = data.follows
    .filter((user) => filter === "all" || user.siteId === filter)
    .filter(
      (user) =>
        tag === "全部" ||
        user.tag === tag ||
        data.tags.some(
          (item) => item.tag === tag && item.userId.includes(user.id),
        ),
    );

  if (playbackMatch)
    return (
      <Suspense fallback={<div className="loading">正在加载播放器</div>}>
        <PlaybackPage
          key={`${playbackMatch[1]}:${playbackMatch[2]}`}
          site={playbackMatch[1]}
          roomId={playbackMatch[2]}
        />
      </Suspense>
    );
  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <img src="/assets/logo.png" alt="" />
          <strong>Simple Live</strong>
          <span>WEB</span>
        </div>
        <nav aria-label="主导航">
          {navigation.map((item) => {
            const Icon = item.icon;
            return (
              <button
                key={item.id}
                aria-current={activeNav === item.id ? "page" : undefined}
                className={activeNav === item.id ? "active" : ""}
                onClick={() => go(item.id)}
              >
                <Icon size={20} />
                <span>{item.label}</span>
              </button>
            );
          })}
        </nav>
        <div className="sidebar-foot">
          <button onClick={() => go("sync")}>
            <Cloud size={19} />
            数据同步
          </button>
          <button className="profile-mini" onClick={() => go("mine")}>
            <span className="avatar">
              <User size={15} />
            </span>
            <span>本地数据</span>
            <ChevronRight size={16} />
          </button>
        </div>
      </aside>
      <main className={`main ${isCatalog ? "has-search" : ""}`}>
        <header className="topbar">
          <div className="crumb">
            {secondary && (
              <button
                className="icon-button"
                aria-label="返回我的"
                title="返回我的"
                onClick={() => go("mine")}
              >
                <ArrowLeft size={18} />
              </button>
            )}
            <span>{pageNames[page]}</span>
          </div>
          {isCatalog && (
            <form
              className="search"
              onSubmit={(event) => {
                event.preventDefault();
                setSearch(query.trim());
              }}
            >
              <Search size={17} />
              <input
                value={query}
                maxLength={100}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="搜索直播间或主播"
                aria-label="搜索直播间或主播"
              />
              {query && (
                <button
                  type="button"
                  aria-label="清空搜索"
                  onClick={() => {
                    setQuery("");
                    setSearch("");
                  }}
                >
                  <X size={15} />
                </button>
              )}
              <button type="submit" aria-label="搜索" title="搜索">
                <ChevronRight size={17} />
              </button>
            </form>
          )}
          <div className="top-actions">
            <button
              className="icon-button"
              title="切换主题"
              aria-label="切换主题"
              onClick={() =>
                setTheme(
                  theme === "dark"
                    ? "light"
                    : theme === "light"
                      ? "system"
                      : "dark",
                )
              }
            >
              {theme === "dark" ? (
                <Moon size={19} />
              ) : theme === "light" ? (
                <Sun size={19} />
              ) : (
                <Monitor size={19} />
              )}
            </button>
            <button
              className="icon-button"
              title="数据同步"
              aria-label="数据同步"
              onClick={() => go("sync")}
            >
              <Cloud size={19} />
            </button>
          </div>
        </header>
        {storageError && (
          <div className="alert error">
            <span>{storageError}</span>
            <button
              title="导出原始数据"
              onClick={() =>
                change(() => download(rawLibrary(), "SimpleLive-recovery.json"))
              }
            >
              <Download size={17} />
            </button>
            <button
              title="清除损坏数据"
              onClick={() =>
                change(() => {
                  if (
                    !confirm("请确认已导出原始数据。清除后不可撤销，是否继续？")
                  )
                    return;
                  resetLibrary();
                  const next = emptyLibrary();
                  library.current = next;
                  setData(next);
                  setStorageError("");
                })
              }
            >
              <Trash2 size={17} />
            </button>
          </div>
        )}
        {isCatalog && (
          <Catalog
            key={page}
            site={site}
            onSite={setSite}
            search={search}
            categories={page === "category"}
            onFollow={toggleFollow}
            follows={data.follows}
            onOpenPlayback={(room) => openPlayback(room.siteId, room.roomId)}
          />
        )}
        {page === "follow" && (
          <FollowPage
            data={data}
            following={following}
            filter={filter}
            setFilter={setFilter}
            tag={tag}
            setTag={setTag}
            onFollow={toggleFollow}
            onAdd={() => setAddFollow(true)}
            onHistory={() => go("history")}
            onRemoveTag={(name) =>
              change(() => {
                const current = library.current;
                commit({
                  ...current,
                  follows: current.follows.map((user) =>
                    user.tag === name ? { ...user, tag: "全部" } : user,
                  ),
                  tags: current.tags.filter((item) => item.tag !== name),
                });
                setTag("全部");
              })
            }
            onEdit={setEditing}
          />
        )}
        {page === "mine" && (
          <Mine onNavigate={go} data={data} theme={theme} setTheme={setTheme} />
        )}
        {page === "history" && (
          <HistoryPage
            data={data}
            onFollow={toggleFollow}
            onRemove={(id) =>
              change(() =>
                commit({
                  ...library.current,
                  histories: library.current.histories.filter(
                    (item) => item.id !== id,
                  ),
                }),
              )
            }
            onClear={() =>
              change(() => {
                if (confirm("清空全部历史记录？"))
                  commit({ ...library.current, histories: [] });
              })
            }
          />
        )}
        {page === "blocked" && (
          <Blocked
            data={data}
            commit={(next) => commit(next)}
            notify={notify}
          />
        )}
        <div hidden={page !== "sync"}>
          <Sync
            data={data}
            commit={(next, expected) => commit(next, expected)}
            notify={notify}
          />
        </div>
      </main>
      {editing && (
        <TagDialog
          value={editing}
          tags={data.tags.map((item) => item.tag)}
          onClose={() => setEditing(null)}
          onSave={saveTag}
        />
      )}
      {addFollow && (
        <AddFollow
          onClose={() => setAddFollow(false)}
          onSave={(user) =>
            change(() => {
              if (library.current.follows.some((item) => item.id === user.id))
                throw new Error("此主播已经在关注列表中");
              commit({
                ...library.current,
                follows: [...library.current.follows, user],
              });
              setAddFollow(false);
            })
          }
        />
      )}
      {toast && (
        <div className="toast" role="status">
          {toast}
        </div>
      )}
    </div>
  );
}
