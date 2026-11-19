import { lazy, Suspense, useEffect, useRef, useState } from "react";
import { App as AntApp, Button, Input, Tooltip } from "antd";
import { ArrowLeft, Cloud, Download, RefreshCw, Trash2 } from "lucide-react";
import { Catalog } from "../features/catalog/Catalog";
import { Sync } from "../features/sync/Sync";
import { FollowPage } from "../pages/follow/FollowPage";
import { Mine } from "../pages/mine/MinePage";
import { HistoryPage } from "../pages/history/HistoryPage";
import { Blocked } from "../pages/blocked/BlockedPage";
import { AccountPage } from "../pages/accounts/AccountPage";
import { TagDialog } from "../features/follow/TagDialog";
import { AddFollow } from "../features/follow/AddFollow";
import { openPlayback, type Page } from "./routes";
import { Sidebar } from "./Sidebar";
import { ThemePicker } from "./ThemePicker";
import { useAppearance } from "./AppearanceProvider";
import {
  hydrateFollowAvatar,
  needsFollowAvatar,
} from "../features/follow/profile";
const PlaybackPage = lazy(() =>
  import("../pages/playback/PlaybackPage").then((module) => ({
    default: module.PlaybackPage,
  })),
);
import {
  download,
  loadLibrary,
  rawLibrary,
  resetLibrary,
  saveLibrary,
  type Follow,
  type History,
  type Library,
  type Room,
} from "../services/libraryData";
import { refreshLibrary, watchLibrary } from "../stores/libraryStorage";
import { usePreferences } from "../stores/preferencesStorage";

const pageNames: Record<Page, string> = {
  home: "首页",
  follow: "我的关注",
  category: "全部分类",
  mine: "我的",
  sync: "数据同步",
  history: "历史记录",
  blocked: "弹幕屏蔽词",
  accounts: "账号管理",
};
const validPage = (): Page => {
  const value = location.hash.slice(1);
  return Object.hasOwn(pageNames, value) ? (value as Page) : "home";
};
export function App() {
  const { mode: theme, setMode: setTheme } = useAppearance();
  const { message, modal } = AntApp.useApp();
  const { error: preferencesError } = usePreferences();
  const [page, setPage] = useState<Page>(validPage);
  const [historyParent, setHistoryParent] = useState<"follow" | "mine">(
    "follow",
  );
  const playbackMatch = location.pathname.match(
    /^\/live\/(bilibili|douyu|huya|douyin)\/([A-Za-z0-9_-]{1,100})$/,
  );
  const [site, setSite] = useState("bilibili");
  const [data, setData] = useState(() => loadLibrary().data);
  const [storageError, setStorageError] = useState(() => loadLibrary().error);
  const [storageCorrupt, setStorageCorrupt] = useState(
    () => loadLibrary().corrupt,
  );
  const [query, setQuery] = useState("");
  const [search, setSearch] = useState("");
  const [editing, setEditing] = useState<Follow | null>(null);
  const [addFollow, setAddFollow] = useState(false);
  const [tag, setTag] = useState("全部");
  const [filter, setFilter] = useState("all");
  const library = useRef(data);
  library.current = data;

  useEffect(() => {
    if (preferencesError)
      void message.error({ key: "preferences-error", content: preferencesError });
  }, [preferencesError, message]);

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
    const onStorage = () => {
      const loaded = loadLibrary();
      library.current = loaded.data;
      setData(loaded.data);
      setStorageError(loaded.error);
      setStorageCorrupt(loaded.corrupt);
    };
    const stop = watchLibrary(onStorage);
    return () => {
      stop();
    };
  }, []);

  function notify(text: string) {
    void message.open({
      type: /失败|错误|损坏/.test(text) ? "error" : "success",
      content: text,
      duration: 4,
    });
  }
  async function commit(next: Library, expected?: Library) {
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
    await saveLibrary(next);
  }
  async function change(action: () => void | Promise<void>) {
    try {
      await action();
    } catch (error) {
      notify(error instanceof Error ? error.message : "操作失败");
    }
  }
  function go(next: Page) {
    if (next === "history")
      setHistoryParent(page === "follow" ? "follow" : "mine");
    location.hash = next;
  }
  function toggleFollow(room: Room | Follow | History) {
    void change(async () => {
      const id = `${room.siteId}_${room.roomId}`;
      const current = library.current;
      const exists = current.follows.some((user) => user.id === id);
      await commit({
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
      if (!exists && (!("face" in room) || needsFollowAvatar(room.face)))
        void hydrateFollowAvatar(room.siteId, room.roomId);
    });
  }
  function saveTag(name: string) {
    void change(async () => {
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
      await commit({
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
  const secondary = ["sync", "history", "blocked", "accounts"].includes(page);
  const activeNav =
    page === "history" ? historyParent : secondary ? "mine" : page;
  const selectedTag = data.tags.some((item) => item.tag === tag) ? tag : "全部";
  const following = data.follows.filter(
    (user) =>
      selectedTag === "全部" ||
      user.tag === selectedTag ||
      data.tags.some(
        (item) => item.tag === selectedTag && item.userId.includes(user.id),
      ),
  );

  if (playbackMatch)
    return (
      <Suspense fallback={null}>
        <PlaybackPage
          key={`${playbackMatch[1]}:${playbackMatch[2]}`}
          site={playbackMatch[1]}
          roomId={playbackMatch[2]}
        />
      </Suspense>
    );
  return (
    <div className="app-shell">
      <Sidebar activePage={activeNav} onNavigate={go} />
      <main className={`main ${isCatalog ? "has-search" : ""}`}>
        <header className="topbar">
          <div className="crumb">
            {secondary && (
              <Button
                type="text"
                icon={<ArrowLeft size={18} />}
                aria-label={
                  page === "history" && historyParent === "follow"
                    ? "返回关注"
                    : "返回我的"
                }
                title={
                  page === "history" && historyParent === "follow"
                    ? "返回关注"
                    : "返回我的"
                }
                onClick={() => go(page === "history" ? historyParent : "mine")}
              />
            )}
            <span>{pageNames[page]}</span>
          </div>
          {isCatalog && (
            <Input.Search
              className="search"
              value={query}
              maxLength={100}
              allowClear
              onChange={(event) => {
                setQuery(event.target.value);
                if (!event.target.value) setSearch("");
              }}
              onSearch={(value) => setSearch(value.trim())}
              placeholder="搜索直播间或主播"
              aria-label="搜索直播间或主播"
            />
          )}
          <div className="top-actions">
            <ThemePicker />
            <Tooltip title="数据同步">
              <Button
                type="text"
                aria-label="数据同步"
                icon={<Cloud size={19} />}
                onClick={() => go("sync")}
              />
            </Tooltip>
          </div>
        </header>
        {storageError && (
          <div className="alert error">
            <span>{storageError}</span>
            <Button
              type="text"
              title="重新读取本地数据"
              aria-label="重新读取本地数据"
              onClick={() => void refreshLibrary()}
              icon={<RefreshCw size={17} />}
            />
            {storageCorrupt && (
              <>
                <Button
                  type="text"
                  title="导出原始数据"
                  onClick={() =>
                    change(() =>
                      download(rawLibrary(), "SimpleLive-recovery.json"),
                    )
                  }
                  icon={<Download size={17} />}
                />
                <Button
                  type="text"
                  danger
                  title="清除损坏数据"
                  onClick={() =>
                    change(async () => {
                      if (
                        !(await modal.confirm({
                          title: "清除损坏数据？",
                          content: "请确认已导出原始数据，清除后不可撤销。",
                          okButtonProps: { danger: true },
                        }))
                      )
                        return;
                      await resetLibrary();
                    })
                  }
                  icon={<Trash2 size={17} />}
                />
              </>
            )}
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
            tag={selectedTag}
            setTag={setTag}
            onFollow={toggleFollow}
            onRemoveHistory={(id) =>
              change(() =>
                commit({
                  ...library.current,
                  histories: library.current.histories.filter(
                    (item) => item.id !== id,
                  ),
                }),
              )
            }
            onClearHistory={() =>
              change(async () => {
                await commit({ ...library.current, histories: [] });
              })
            }
            onAdd={() => setAddFollow(true)}
            notify={notify}
            onRemoveTag={(name) =>
              change(async () => {
                const current = library.current;
                await commit({
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
              change(async () => {
                await commit({ ...library.current, histories: [] });
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
        {page === "accounts" && <AccountPage />}
        <div hidden={page !== "sync"}>
          <Sync
            active={page === "sync"}
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
            change(async () => {
              if (library.current.follows.some((item) => item.id === user.id))
                throw new Error("此主播已经在关注列表中");
              await commit({
                ...library.current,
                follows: [...library.current.follows, user],
              });
              setAddFollow(false);
              void hydrateFollowAvatar(user.siteId, user.roomId);
            })
          }
        />
      )}
    </div>
  );
}
