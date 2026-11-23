import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  App as AntApp,
  Button,
  Dropdown,
  Input,
  Tabs,
  Tag,
  Tooltip,
} from "antd";
import {
  ChevronLeft,
  ChevronRight,
  Copy,
  Flame,
  Heart,
  Info,
  Link2,
  LoaderCircle,
  Plus,
  RefreshCw,
  Share2,
} from "lucide-react";
import { openPlayback, playbackUrl } from "../../app/routes";
import { PlayerSurface } from "../../features/player/components/PlayerSurface";
import { PlayerBoundary } from "../../features/player/components/PlayerBoundary";
import { PlayerSettings } from "../../features/player/components/PlayerSettings";
import { DanmakuPanel } from "../../features/player/components/DanmakuPanel";
import { usePlaybackSession } from "../../features/player/hooks/usePlaybackSession";
import { useDanmaku } from "../../features/danmaku/useDanmaku";
import { createFilter } from "../../features/danmaku/filter";
import { usePlayerSettings } from "../../stores/playerSettings";
import { refreshAccounts } from "../../stores/accountsStorage";
import { useLibrary } from "../../stores/useLibrary";
import { useFollowStatus } from "../../features/follow/useFollowStatus";
import { FollowStatusLabel } from "../../features/follow/FollowStatusLabel";
import { needsFollowAvatar } from "../../features/follow/profile";
import "../../styles/player.css";
import { Picture } from "../../components/Picture";
import { platforms } from "../../app/platforms";
import { formatHeat } from "../../components/formatHeat";
import { playbackApi } from "../../services/playbackApi";
import type { RoomDetail } from "../../types/playback";
import {
  updatePreferences,
  usePreferences,
} from "../../stores/preferencesStorage";

export function PlaybackPage({
  site,
  roomId,
}: {
  site: string;
  roomId: string;
}) {
  const { message, modal } = AntApp.useApp();
  const stage = useRef<HTMLDivElement>(null);
  const frame = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const container = stage.current;
    const playerFrame = frame.current;
    if (!container || !playerFrame) return;
    const resize = () => {
      playerFrame.classList.toggle("is-compact", container.clientWidth < 560);
    };
    const observer = new ResizeObserver(resize);
    observer.observe(container);
    resize();
    return () => observer.disconnect();
  }, []);
  const session = usePlaybackSession(site, roomId);
  const authTipShown = useRef(false);
  useEffect(() => {
    authTipShown.current = false;
  }, [site, roomId]);
  useEffect(() => {
    if (site !== "douyu" || !session.authWarning || authTipShown.current) return;
    authTipShown.current = true;
    void message.warning({
      key: `douyu-auth-${site}-${roomId}`,
      content: session.authWarning.message,
      duration: 6,
    });
    void refreshAccounts().catch(() => {});
  }, [site, roomId, session.authWarning, message]);
  const [paused, setPaused] = useState(true);
  const chat = useDanmaku(site, roomId, session.detail?.status === true, paused);
  const { data, update } = useLibrary();
  const [settings, setSettings] = usePlayerSettings();
  const { data: preferences } = usePreferences();
  const sidebarCollapsed = preferences.playbackSidebarCollapsed;
  const [panel, setPanel] = useState("chat"),
    [keyword, setKeyword] = useState("");
  const showFollows = !sidebarCollapsed && panel === "follows";
  const { statuses: followStatuses } = useFollowStatus(
    data.follows,
    showFollows,
    false,
    true,
  );
  const sidebarFollows = useMemo(
    () =>
      showFollows
        ? [...data.follows].sort(
            (left, right) =>
              Number(followStatuses[right.id]?.status === true) -
              Number(followStatuses[left.id]?.status === true),
          )
        : [],
    [data.follows, followStatuses, showFollows],
  );
  const [status, setStatus] = useState("等待连接");
  const retries = useRef(0),
    historyWritten = useRef(false);
  const id = `${site}_${roomId}`;
  const roomIds = new Set(
    [roomId, session.detail?.canonicalRoomId].filter(Boolean),
  );
  const matchingFollow = data.follows.find(
    (item) => item.siteId === site && roomIds.has(item.roomId),
  );
  const followed = Boolean(matchingFollow);
  const currentFollowed = useRef(followed);
  currentFollowed.current = followed;
  const platform = platforms.find((item) => item.id === site);
  const heatRequest = useRef<AbortController | null>(null);
  const heatBaseline = useRef({ chatOnline: chat.online, detail: session.detail });
  heatBaseline.current = { chatOnline: chat.online, detail: session.detail };
  const [heatLoading, setHeatLoading] = useState(false);
  const [refreshedHeat, setRefreshedHeat] = useState<{
    id: string;
    online: number;
    chatOnline: number | null;
    detail: RoomDetail | null;
  } | null>(null);
  useEffect(() => {
    setHeatLoading(false);
    setRefreshedHeat(null);
    return () => {
      heatRequest.current?.abort();
      heatRequest.current = null;
    };
  }, [site, roomId]);
  // Douyin's websocket totalUser is not the room's display_value heat metric.
  const heat =
    refreshedHeat?.id === id &&
    refreshedHeat.detail === session.detail &&
    (site === "douyin" || refreshedHeat.chatOnline === chat.online)
      ? refreshedHeat.online
      : site === "douyin"
        ? (session.detail?.online ?? 0)
        : (chat.online ?? session.detail?.online ?? 0);
  const refreshHeat = async () => {
    if (heatRequest.current) return;
    const controller = new AbortController();
    heatRequest.current = controller;
    setHeatLoading(true);
    try {
      const room = await playbackApi.detail(site, roomId, controller.signal);
      if (controller.signal.aborted) return;
      setRefreshedHeat({
        id,
        online: room.online,
        ...heatBaseline.current,
      });
    } catch (error) {
      if (!controller.signal.aborted)
        void message.error(
          error instanceof Error ? error.message : "热度刷新失败，请重试",
        );
    } finally {
      if (heatRequest.current === controller) {
        heatRequest.current = null;
        setHeatLoading(false);
      }
    }
  };
  const filter = useMemo(
    () => createFilter(data.blocked, settings.fortune),
    [data.blocked, settings.fortune],
  );
  const messages = useMemo(
    () => chat.messages.filter((item) => filter(item.message)),
    [chat.messages, filter],
  );
  const notify = useCallback(
    (text: string) => {
      void message.open({
        type: /失败|错误/.test(text) ? "error" : "success",
        content: text,
        duration: 4,
      });
    },
    [message],
  );
  useEffect(() => {
    document.title = `${session.detail?.title ?? "直播间"} · Simple Live`;
  }, [session.detail]);
  const perform = (action: () => void | Promise<void>) =>
    Promise.resolve()
      .then(action)
      .catch((reason) =>
        notify(reason instanceof Error ? reason.message : "操作失败"),
      );
  const copy = (text: string, message: string) =>
    perform(async () => {
      await navigator.clipboard.writeText(text);
      notify(message);
    });
  const toggleFollow = () =>
    perform(async () => {
      if (!session.detail) return;
      const room = session.detail;
      let removed = false;
      await update((current) => {
        const ids = new Set(
          current.follows
            .filter((user) => user.siteId === site && roomIds.has(user.roomId))
            .map((user) => user.id),
        );
        removed = ids.size > 0;
        return {
          ...current,
          follows: removed
            ? current.follows.filter((user) => !ids.has(user.id))
            : [
                ...current.follows,
                {
                  id,
                  roomId,
                  siteId: site,
                  userName: room.userName,
                  face: room.userAvatar,
                  addTime: new Date().toISOString(),
                  tag: "全部",
                },
              ],
          tags: removed
            ? current.tags.map((tag) => ({
                ...tag,
                userId: tag.userId.filter((user) => !ids.has(user)),
              }))
            : current.tags,
        };
      });
      notify(removed ? "已取消关注" : "已添加关注");
    });
  useEffect(() => {
    if (
      !status.startsWith("播放中") ||
      !session.detail ||
      historyWritten.current
    )
      return;
    historyWritten.current = true;
    const room = session.detail;
    void (async () => {
      try {
        await update((current) => ({
          ...current,
          histories: [
            ...current.histories.filter((item) => item.id !== id),
            {
              id,
              roomId,
              siteId: site,
              userName: room.userName,
              face: room.userAvatar,
              updateTime: new Date().toISOString(),
            },
          ],
        }));
      } catch (error) {
        historyWritten.current = false;
        notify(error instanceof Error ? error.message : "历史记录保存失败");
      }
    })();
  }, [status, session.detail, id, roomId, site, update, notify]);
  const failed = useCallback(
    (message: string) => {
      notify(message);
      if (message.startsWith("播放失败") && retries.current++ < 2)
        session.refresh();
    },
    [notify, session.refresh],
  );
  const refresh = () => {
    retries.current = 0;
    session.refresh();
    chat.reconnect();
  };
  const addKeyword = () =>
    perform(async () => {
      const word = keyword.trim();
      if (!word) return;
      await update((current) => ({
        ...current,
        blocked: [...new Set([...current.blocked, word])],
      }));
      setKeyword("");
    });
  return (
    <div className="playback-page">
      <main
        className={`playback-main ${sidebarCollapsed ? "is-sidebar-collapsed" : ""}`}
      >
        <section className="video-panel">
          <section className="room-info">
            <Tooltip title="返回关注页">
              <a
                className="room-avatar-link"
                href="/#follow"
                aria-label="返回关注页"
              >
                <Picture
                  src={session.detail?.userAvatar || matchingFollow?.face}
                />
              </a>
            </Tooltip>
            <div className="room-profile">
              <strong title={session.detail?.title}>
                {session.detail?.title || "直播间"}
              </strong>
              <div className="room-meta">
                <span
                  className="room-anchor-name"
                  title={session.detail?.userName}
                >
                  {session.detail?.userName ||
                    matchingFollow?.userName ||
                    "主播"}
                </span>
                <Tooltip title={heat.toLocaleString("en-US")}>
                  <Button
                    type="text"
                    className="room-heat"
                    aria-label="刷新热度"
                    aria-busy={heatLoading}
                    onClick={() => void refreshHeat()}
                    icon={
                      heatLoading ? (
                        <LoaderCircle size={14} className="spin" />
                      ) : (
                        <Flame size={14} />
                      )
                    }
                  >
                    {formatHeat(heat)}
                  </Button>
                </Tooltip>
                <span className="room-platform">
                  {platform && <img src={`/assets/${platform.logo}`} alt="" />}
                  {platform?.name ?? site}
                </span>
              </div>
            </div>
            <div className="room-actions">
              <span
                className="room-connection"
                title={session.error || status}
                role="status"
              >
                {session.switching ? "切换线路中" : status}
              </span>
              <Dropdown
                trigger={["click"]}
                placement="bottomRight"
                menu={{
                  items: [
                    {
                      key: "room",
                      label: "复制直播间链接",
                      icon: <Link2 size={16} />,
                      disabled: !session.detail,
                    },
                    {
                      key: "stream",
                      label: "复制播放链接",
                      icon: <Copy size={16} />,
                      disabled: !session.source,
                    },
                  ],
                  onClick: ({ key }) => {
                    if (key === "room" && session.detail)
                      void copy(session.detail.url, "直播间链接已复制");
                    if (key === "stream" && session.source)
                      void copy(session.source.url, "播放链接已复制");
                  },
                }}
              >
                <Button
                  type="text"
                  icon={<Share2 size={18} />}
                  title="分享"
                  aria-label="分享"
                />
              </Dropdown>
              <Tooltip title={followed ? "取消关注" : "关注"}>
                <Button
                  type="text"
                  disabled={!session.detail}
                  className={followed ? "room-followed" : ""}
                  aria-label={followed ? "取消关注" : "关注"}
                  title={followed ? "取消关注" : "关注"}
                  aria-pressed={followed}
                  onClick={() => {
                    if (!followed) {
                      void toggleFollow();
                      return;
                    }
                    modal.confirm({
                      title: `取消关注 ${session.detail?.userName ?? "此主播"}？`,
                      onOk: () =>
                        currentFollowed.current ? toggleFollow() : undefined,
                    });
                  }}
                  icon={
                    <Heart
                      size={20}
                      fill={followed ? "currentColor" : "none"}
                    />
                  }
                />
              </Tooltip>
            </div>
          </section>
          <div className="video-stage" ref={stage}>
            <div className="player-frame" ref={frame}>
              <PlayerBoundary>
                <PlayerSurface
                  danmakuContainer={stage}
                  source={session.source}
                  loading={session.loading && !session.source}
                  refreshing={session.loading}
                  switching={session.switching}
                  settings={settings}
                  messages={messages}
                  status={status}
                  onState={setStatus}
                  onPausedChange={setPaused}
                  onFailure={failed}
                  onConfirmed={session.confirm}
                  qualities={session.qualities}
                  quality={session.quality}
                  sources={session.sources}
                  onQuality={(quality) => void session.choose(quality)}
                  onLine={session.selectLine}
                  onRefresh={refresh}
                  onSettings={setSettings}
                />
              </PlayerBoundary>
            </div>
            {((session.error && !session.source) ||
              (!session.loading &&
                session.detail &&
                !session.detail.status)) && (
              <div className="player-error">
                <Info size={28} />
                <strong>{session.error || "主播暂未开播"}</strong>
                <Button
                  type="primary"
                  onClick={refresh}
                  icon={<RefreshCw size={16} />}
                >
                  重新连接
                </Button>
              </div>
            )}
          </div>
        </section>
        <aside
          id="playback-sidebar"
          className="playback-sidebar"
          hidden={sidebarCollapsed}
        >
          {!sidebarCollapsed && (
            <Tabs
              activeKey={panel}
              onChange={setPanel}
              tabBarGutter={20}
              items={[
                ["chat", "聊天"],
                ...(site === "bilibili" ? [["sc", "SC"]] : []),
                ["follows", "关注"],
                ["settings", "弹幕设置"],
              ].map(([key, label]) => ({ key, label }))}
            />
          )}
          {!sidebarCollapsed && panel === "chat" && (
            <DanmakuPanel
              messages={messages.filter((item) => item.type === "chat")}
              status={chat.status}
              onReconnect={chat.reconnect}
            />
          )}
          {!sidebarCollapsed && panel === "sc" && (
            <div className="chat-list">
              {messages
                .filter((item) => item.type === "superChat")
                .map((item) => (
                  <article className="sc-message" key={item.id}>
                    <strong>
                      {item.userName} · ¥{item.price}
                    </strong>
                    <p>{item.message}</p>
                  </article>
                ))}
            </div>
          )}
          {showFollows && (
            <div className="chat-list">
              {sidebarFollows.map((user) => {
                const state = followStatuses[user.id];
                const offline = state?.status === false;
                const avatar = state?.face || user.face;
                const heat = state?.status === true ? state.online : undefined;
                return (
                  <a
                    className="follow-link"
                    key={user.id}
                    href={
                      offline ? undefined : playbackUrl(user.siteId, user.roomId)
                    }
                    target="_blank"
                    rel="noopener"
                    onClick={(event) => {
                      event.preventDefault();
                      if (!offline) openPlayback(user.siteId, user.roomId);
                    }}
                    role={offline ? "link" : undefined}
                    aria-disabled={offline || undefined}
                  >
                    {!needsFollowAvatar(avatar) && (
                      <Picture src={avatar} className="follow-link-avatar" />
                    )}
                    <div className="follow-link-profile">
                      <span className="follow-link-name" title={user.userName}>
                        {user.userName}
                      </span>
                      {heat !== undefined && Number.isFinite(heat) && (
                        <Tooltip title={heat.toLocaleString("en-US")}>
                          <span className="follow-link-heat">
                            <Flame size={12} aria-hidden="true" />
                            {formatHeat(heat)}
                          </span>
                        </Tooltip>
                      )}
                    </div>
                    <FollowStatusLabel value={state} />
                  </a>
                );
              })}
            </div>
          )}
          {!sidebarCollapsed && panel === "settings" && (
            <div className="playback-settings-panel">
              <PlayerSettings value={settings} onChange={setSettings} />
              <form
                className="blocked-add"
                onSubmit={(event) => {
                  event.preventDefault();
                  void addKeyword();
                }}
              >
                <Input
                  aria-label="屏蔽词"
                  value={keyword}
                  maxLength={100}
                  placeholder="屏蔽关键词"
                  onChange={(event) => setKeyword(event.target.value)}
                />
                <Button
                  type="primary"
                  htmlType="submit"
                  disabled={!keyword.trim()}
                  icon={<Plus size={15} />}
                >
                  添加
                </Button>
              </form>
              <div className="word-list">
                {data.blocked.map((word) => (
                  <Tag
                    key={word}
                    closable
                    onClose={(event) => {
                      event.preventDefault();
                      void perform(() =>
                        update((current) => ({
                          ...current,
                          blocked: current.blocked.filter(
                            (item) => item !== word,
                          ),
                        })),
                      );
                    }}
                  >
                    {word}
                  </Tag>
                ))}
              </div>
            </div>
          )}
        </aside>
        <div className="playback-sidebar-edge">
          <button
            className="sidebar-toggle playback-sidebar-toggle"
            title={sidebarCollapsed ? "展开侧栏" : "收起侧栏"}
            aria-label={sidebarCollapsed ? "展开侧栏" : "收起侧栏"}
            aria-expanded={!sidebarCollapsed}
            aria-controls="playback-sidebar"
            onClick={() =>
              updatePreferences({ playbackSidebarCollapsed: !sidebarCollapsed })
            }
          >
            {sidebarCollapsed ? (
              <ChevronLeft size={17} />
            ) : (
              <ChevronRight size={17} />
            )}
          </button>
        </div>
      </main>
    </div>
  );
}
