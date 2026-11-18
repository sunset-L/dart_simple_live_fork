import React, { useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  ArrowLeft,
  Check,
  ChevronRight,
  Cloud,
  Compass,
  Download,
  Grid2X2,
  Heart,
  History as HistoryIcon,
  Monitor,
  Moon,
  Plus,
  Search,
  Settings,
  Shield,
  Sun,
  Trash2,
  User,
  X,
} from "lucide-react";
import { Catalog, Empty, Picture } from "./Catalog";
import { Sync } from "./Sync";
import {
  download,
  emptyLibrary,
  loadLibrary,
  platforms,
  rawLibrary,
  resetLibrary,
  saveLibrary,
  type Follow,
  type History,
  type Library,
  type Room,
} from "./data";
import "./style.css";

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

function App() {
  const [page, setPage] = useState<Page>(validPage);
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

function FollowPage({
  data,
  following,
  filter,
  setFilter,
  tag,
  setTag,
  onFollow,
  onRemoveTag,
  onEdit,
  onAdd,
  onHistory,
}: {
  data: Library;
  following: Follow[];
  filter: string;
  setFilter: (value: string) => void;
  tag: string;
  setTag: (value: string) => void;
  onFollow: (item: Follow) => void;
  onRemoveTag: (name: string) => void;
  onEdit: (item: Follow) => void;
  onAdd: () => void;
  onHistory: () => void;
}) {
  const tags = [...new Set(["全部", ...data.tags.map((item) => item.tag)])];
  return (
    <div className="follow-content">
      <div className="content-heading">
        <div>
          <h1>我的关注</h1>
          <span className="muted">{following.length} 位主播</span>
        </div>
        <div className="actions compact">
          <button title="历史记录" aria-label="历史记录" onClick={onHistory}>
            <HistoryIcon size={18} />
          </button>
          <button className="primary" onClick={onAdd}>
            <Plus size={17} />
            添加关注
          </button>
        </div>
      </div>
      <div className="filter-bar">
        <div className="tabs" aria-label="平台筛选">
          {[
            ["all", "全部平台"],
            ...platforms.map((item) => [item.id, item.name]),
          ].map(([id, label]) => (
            <button
              key={id}
              aria-pressed={filter === id}
              className={filter === id ? "active" : ""}
              onClick={() => setFilter(id)}
            >
              {label}
            </button>
          ))}
        </div>
        <div className="tag-list">
          {tags.map((item) => (
            <button
              key={item}
              aria-pressed={tag === item}
              className={tag === item ? "selected" : ""}
              onClick={() => setTag(item)}
            >
              {item}
            </button>
          ))}
        </div>
      </div>
      {following.length ? (
        <div className="follow-grid">
          {following.map((item) => (
            <article className="follow-card" key={item.id}>
              <Picture src={item.face} />
              <div className="follow-info">
                <strong>{item.userName}</strong>
                <span>
                  {platforms.find((platform) => platform.id === item.siteId)
                    ?.name ?? item.siteId}{" "}
                  · {item.tag}
                </span>
                <small>房间 {item.roomId}</small>
              </div>
              <button
                title="设置标签"
                aria-label={`设置 ${item.userName} 的标签`}
                onClick={() => onEdit(item)}
              >
                <Settings size={16} />
              </button>
              <button
                title="取消关注"
                aria-label={`取消关注 ${item.userName}`}
                onClick={() => {
                  if (confirm(`取消关注 ${item.userName}？`)) onFollow(item);
                }}
              >
                <Trash2 size={16} />
              </button>
            </article>
          ))}
        </div>
      ) : (
        <Empty
          title={data.follows.length ? "没有符合条件的关注" : "暂无关注"}
        />
      )}
      {data.tags.length > 0 && (
        <div className="tag-manage">
          <span>标签</span>
          {data.tags.map((item) => (
            <button
              key={item.id}
              title={`删除标签 ${item.tag}`}
              onClick={() => {
                if (confirm(`删除标签“${item.tag}”？主播不会被取消关注。`))
                  onRemoveTag(item.tag);
              }}
            >
              <span>{item.tag}</span>
              <X size={14} />
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function Mine({
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
          <div className="segmented">
            {[
              ["system", "跟随系统"],
              ["light", "浅色"],
              ["dark", "深色"],
            ].map(([id, label]) => (
              <button
                key={id}
                aria-pressed={theme === id}
                className={theme === id ? "selected" : ""}
                onClick={() => setTheme(id)}
              >
                {label}
              </button>
            ))}
          </div>
        </div>
      </section>
    </div>
  );
}
function HistoryPage({
  data,
  onFollow,
  onRemove,
  onClear,
}: {
  data: Library;
  onFollow: (item: History) => void;
  onRemove: (id: string) => void;
  onClear: () => void;
}) {
  return (
    <div className="follow-content">
      <div className="content-heading">
        <h1>历史记录</h1>
        {data.histories.length > 0 && (
          <button className="quiet-button danger-text" onClick={onClear}>
            <Trash2 size={17} />
            清空
          </button>
        )}
      </div>
      {data.histories.length ? (
        <div className="follow-grid">
          {[...data.histories]
            .sort((a, b) => Date.parse(b.updateTime) - Date.parse(a.updateTime))
            .map((item) => {
              const followed = data.follows.some((user) => user.id === item.id);
              return (
                <article className="follow-card" key={item.id}>
                  <Picture src={item.face} />
                  <div className="follow-info">
                    <strong>{item.userName}</strong>
                    <span>
                      {platforms.find((platform) => platform.id === item.siteId)
                        ?.name ?? item.siteId}
                    </span>
                    <small>
                      {new Date(item.updateTime).toLocaleString("zh-CN")}
                    </small>
                  </div>
                  <button
                    title={followed ? "取消关注" : "添加关注"}
                    aria-label={followed ? "取消关注" : "添加关注"}
                    onClick={() => onFollow(item)}
                  >
                    <Heart
                      size={16}
                      fill={followed ? "currentColor" : "none"}
                    />
                  </button>
                  <button
                    title="删除记录"
                    aria-label="删除记录"
                    onClick={() => onRemove(item.id)}
                  >
                    <Trash2 size={16} />
                  </button>
                </article>
              );
            })}
        </div>
      ) : (
        <Empty title="暂无历史记录" />
      )}
    </div>
  );
}
function Blocked({
  data,
  commit,
  notify,
}: {
  data: Library;
  commit: (data: Library) => void;
  notify: (message: string) => void;
}) {
  const [value, setValue] = useState("");
  function update(words: string[]) {
    try {
      commit({ ...data, blocked: words });
      setValue("");
    } catch (error) {
      notify(error instanceof Error ? error.message : "保存失败");
    }
  }
  function add() {
    if (value.trim()) update([...new Set([...data.blocked, value.trim()])]);
  }
  return (
    <div className="settings-content">
      <div className="section-heading">
        <h2>弹幕屏蔽词</h2>
        <Shield size={28} className="accent" />
      </div>
      <form
        className="blocked-add"
        onSubmit={(event) => {
          event.preventDefault();
          add();
        }}
      >
        <input
          aria-label="屏蔽词"
          value={value}
          onChange={(event) => setValue(event.target.value)}
          maxLength={100}
          placeholder="添加屏蔽词"
        />
        <button className="primary" disabled={!value.trim()}>
          <Plus size={17} />
          添加
        </button>
      </form>
      <div className="word-list">
        {data.blocked.map((word) => (
          <span key={word}>
            {word}
            <button
              title={`移除 ${word}`}
              aria-label={`移除 ${word}`}
              onClick={() =>
                update(data.blocked.filter((item) => item !== word))
              }
            >
              <X size={13} />
            </button>
          </span>
        ))}
      </div>
    </div>
  );
}
function Modal({
  title,
  onClose,
  children,
}: {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    dialog.current?.showModal();
  }, []);
  return (
    <dialog ref={dialog} className="modal" onCancel={onClose}>
      <div className="modal-head">
        <h2>{title}</h2>
        <button type="button" title="关闭" aria-label="关闭" onClick={onClose}>
          <X size={18} />
        </button>
      </div>
      {children}
    </dialog>
  );
}
function TagDialog({
  value,
  tags,
  onClose,
  onSave,
}: {
  value: Follow;
  tags: string[];
  onClose: () => void;
  onSave: (name: string) => void;
}) {
  const [name, setName] = useState(value.tag);
  return (
    <Modal title="设置标签" onClose={onClose}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (name.trim()) onSave(name.trim());
        }}
      >
        <input
          autoFocus
          aria-label="标签名称"
          value={name}
          onChange={(event) => setName(event.target.value)}
          list="tag-options"
          maxLength={40}
        />
        <datalist id="tag-options">
          {[...new Set(["全部", ...tags])].map((tag) => (
            <option key={tag} value={tag} />
          ))}
        </datalist>
        <div className="modal-actions">
          <button type="button" onClick={onClose}>
            取消
          </button>
          <button className="primary" disabled={!name.trim()}>
            <Check size={16} />
            保存
          </button>
        </div>
      </form>
    </Modal>
  );
}
function AddFollow({
  onClose,
  onSave,
}: {
  onClose: () => void;
  onSave: (user: Follow) => void;
}) {
  const [siteId, setSite] = useState("bilibili");
  const [roomId, setRoom] = useState("");
  const [userName, setName] = useState("");
  return (
    <Modal title="添加关注" onClose={onClose}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          const id = roomId.trim();
          if (!id || !userName.trim()) return;
          onSave({
            id: `${siteId}_${id}`,
            roomId: id,
            siteId,
            userName: userName.trim(),
            face: "",
            addTime: new Date().toISOString(),
            tag: "全部",
          });
        }}
      >
        <label className="field">
          直播平台
          <select
            value={siteId}
            onChange={(event) => setSite(event.target.value)}
          >
            {platforms.map((site) => (
              <option key={site.id} value={site.id}>
                {site.name}
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          房间号
          <input
            required
            maxLength={100}
            pattern="[A-Za-z0-9_-]+"
            value={roomId}
            onChange={(event) => setRoom(event.target.value)}
          />
        </label>
        <label className="field">
          主播名称
          <input
            required
            maxLength={100}
            value={userName}
            onChange={(event) => setName(event.target.value)}
          />
        </label>
        <div className="modal-actions">
          <button type="button" onClick={onClose}>
            取消
          </button>
          <button className="primary">
            <Plus size={16} />
            添加
          </button>
        </div>
      </form>
    </Modal>
  );
}

createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
