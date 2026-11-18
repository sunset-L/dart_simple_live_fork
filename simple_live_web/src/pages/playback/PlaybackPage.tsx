import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowLeft,
  Copy,
  Heart,
  Info,
  Link2,
  LoaderCircle,
  RefreshCw,
  Share2,
  X,
} from "lucide-react";
import { safeImage } from "../../services/media";
import { openPlayback, playbackUrl } from "../../app/routes";
import {
  PlayerSurface,
  type PlayerHandle,
} from "../../features/player/components/PlayerSurface";
import { PlayerSettings } from "../../features/player/components/PlayerSettings";
import { PlaybackToolbar } from "../../features/player/components/PlaybackToolbar";
import { PlaybackInfo } from "../../features/player/components/PlaybackInfo";
import { DanmakuPanel } from "../../features/player/components/DanmakuPanel";
import { usePlaybackSession } from "../../features/player/hooks/usePlaybackSession";
import { useDanmaku } from "../../features/danmaku/useDanmaku";
import { createFilter } from "../../features/danmaku/filter";
import { usePlayerSettings } from "../../stores/playerSettings";
import { useLibrary } from "../../stores/useLibrary";
import { useFollowStatus } from "../../features/follow/useFollowStatus";
import { FollowStatusLabel } from "../../features/follow/FollowStatusLabel";
import "../../styles/player.css";

export function PlaybackPage({
  site,
  roomId,
}: {
  site: string;
  roomId: string;
}) {
  const session = usePlaybackSession(site, roomId);
  const chat = useDanmaku(site, roomId, session.detail?.status === true);
  const { data, update } = useLibrary();
  const [settings, setSettings] = usePlayerSettings();
  const [locked, setLocked] = useState(false),
    [fit, setFit] = useState("contain");
  const [panel, setPanel] = useState("chat"),
    [keyword, setKeyword] = useState("");
  const followStatus = useFollowStatus(data.follows, panel === "follows");
  const [handle, setHandle] = useState<PlayerHandle | null>(null);
  const [status, setStatus] = useState("等待连接"),
    [toast, setToast] = useState("");
  const toastTimer = useRef<ReturnType<typeof setTimeout> | undefined>(
    undefined,
  );
  const retries = useRef(0),
    historyWritten = useRef(false);
  const id = `${site}_${roomId}`;
  const followed = data.follows.some((item) => item.id === id);
  const filter = useMemo(
    () => createFilter(data.blocked, settings.fortune),
    [data.blocked, settings.fortune],
  );
  const messages = useMemo(
    () => chat.messages.filter((item) => filter(item.message)),
    [chat.messages, filter],
  );
  const notify = useCallback((text: string) => {
    setToast(text);
    clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(""), 5000);
  }, []);
  useEffect(() => () => clearTimeout(toastTimer.current), []);
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
      await update((current) => ({
        ...current,
        follows: followed
          ? current.follows.filter((user) => user.id !== id)
          : [
              ...current.follows.filter((user) => user.id !== id),
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
        tags: followed
          ? current.tags.map((tag) => ({
              ...tag,
              userId: tag.userId.filter((user) => user !== id),
            }))
          : current.tags,
      }));
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
      <header className="playback-header">
        <a
          className="icon-button"
          href="/"
          title="返回首页"
          aria-label="返回首页"
        >
          <ArrowLeft size={19} />
        </a>
        <div className="playback-title">
          <strong>{session.detail?.title ?? "直播间"}</strong>
          <span>{session.detail?.userName ?? `${site} · ${roomId}`}</span>
        </div>
        <button
          className="icon-button"
          title="分享播放页"
          aria-label="分享播放页"
          onClick={() =>
            void perform(async () => {
              if (navigator.share)
                await navigator.share({
                  title: session.detail?.title,
                  url: location.href,
                });
              else await navigator.clipboard.writeText(location.href);
            })
          }
        >
          <Share2 size={18} />
        </button>
      </header>
      <main className="playback-main">
        <section className="video-panel">
          <div className="video-stage">
            <PlayerSurface
              source={session.source}
              settings={settings}
              messages={messages}
              locked={locked}
              fit={fit}
              onReady={setHandle}
              onState={setStatus}
              onFailure={failed}
              onConfirmed={session.confirm}
              qualities={session.qualities}
              sources={session.sources}
              onQuality={(quality) => void session.choose(quality)}
              onLine={session.selectLine}
              onSettings={setSettings}
            />
            {session.loading && !session.source && (
              <div className="player-loading">
                <LoaderCircle className="spin" size={30} />
                <span>正在读取直播信息</span>
              </div>
            )}
            {((session.error && !session.source) ||
              (session.detail && !session.detail.status)) && (
              <div className="player-error">
                <Info size={28} />
                <strong>{session.error || "主播暂未开播"}</strong>
                <button onClick={refresh}>
                  <RefreshCw size={16} />
                  重新连接
                </button>
              </div>
            )}
          </div>
          <PlaybackToolbar
            locked={locked}
            onLock={() => setLocked((value) => !value)}
            onRefresh={refresh}
            danmaku={settings.enabled}
            onDanmaku={() => setSettings({ enabled: !settings.enabled })}
            switching={session.switching}
            qualities={session.qualities}
            quality={session.quality}
            sources={session.sources}
            source={session.source}
            onQuality={(quality) => void session.choose(quality)}
            onLine={session.selectLine}
            onPanel={(next) => setPanel(panel === next ? "chat" : next)}
          />
          <div className="playback-state" role="status">
            {session.switching ? "正在获取新线路" : status}
            {session.error && <span className="error">{session.error}</span>}
          </div>
          <div className="playback-actions">
            <button
              disabled={!session.detail}
              onClick={() => void copy(session.detail!.url, "直播间链接已复制")}
            >
              <Link2 size={16} />
              直播间链接
            </button>
            <button
              disabled={!session.source}
              onClick={() => void copy(session.source!.url, "播放直链已复制")}
            >
              <Copy size={16} />
              播放直链
            </button>
            <button
              onClick={() =>
                void copy(session.error || status, "诊断信息已复制")
              }
            >
              <Info size={16} />
              复制诊断
            </button>
          </div>
        </section>
        <aside className="playback-sidebar">
          <section className="room-info">
            <img src={safeImage(session.detail?.userAvatar)} alt="" />
            <div>
              <strong>{session.detail?.userName ?? roomId}</strong>
              <span>
                {(chat.online ?? session.detail?.online ?? 0).toLocaleString(
                  "zh-CN",
                )}{" "}
                人气
              </span>
            </div>
            <button
              disabled={!session.detail}
              className="icon-button"
              aria-label={followed ? "取消关注" : "关注"}
              title={followed ? "取消关注" : "关注"}
              onClick={() => void toggleFollow()}
            >
              <Heart size={19} fill={followed ? "currentColor" : "none"} />
            </button>
          </section>
          <div className="tabs">
            {[
              ["chat", "聊天"],
              ...(site === "bilibili" ? [["sc", "SC"]] : []),
              ["follows", "关注"],
              ["settings", "设置"],
              ["info", "信息"],
            ].map(([key, label]) => (
              <button
                key={key}
                className={panel === key ? "active" : ""}
                onClick={() => setPanel(key)}
              >
                {label}
              </button>
            ))}
          </div>
          {panel === "chat" && (
            <DanmakuPanel
              messages={messages.filter((item) => item.type === "chat")}
              status={chat.status}
              onReconnect={chat.reconnect}
            />
          )}
          {panel === "sc" && (
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
          {panel === "follows" && (
            <div className="chat-list">
              {data.follows.map((user) => (
                <a
                  className="follow-link"
                  key={user.id}
                  href={playbackUrl(user.siteId, user.roomId)}
                  target="_blank"
                  rel="noopener"
                  onClick={(event) => {
                    event.preventDefault();
                    openPlayback(user.siteId, user.roomId);
                  }}
                >
                  {user.userName}
                  <FollowStatusLabel value={followStatus.statuses[user.id]} />
                </a>
              ))}
            </div>
          )}
          {panel === "settings" && (
            <>
              <PlayerSettings
                value={settings}
                onChange={setSettings}
                fit={fit}
                onFit={setFit}
              />
              <form
                className="blocked-add"
                onSubmit={(event) => {
                  event.preventDefault();
                  void addKeyword();
                }}
              >
                <input
                  aria-label="屏蔽词"
                  value={keyword}
                  maxLength={100}
                  placeholder="屏蔽关键词"
                  onChange={(event) => setKeyword(event.target.value)}
                />
                <button className="primary" disabled={!keyword.trim()}>
                  添加
                </button>
              </form>
              <div className="word-list">
                {data.blocked.map((word) => (
                  <span key={word}>
                    {word}
                    <button
                      title={`移除 ${word}`}
                      onClick={() =>
                        void perform(() =>
                          update((current) => ({
                            ...current,
                            blocked: current.blocked.filter(
                              (item) => item !== word,
                            ),
                          })),
                        )
                      }
                    >
                      <X size={13} />
                    </button>
                  </span>
                ))}
              </div>
            </>
          )}
          {panel === "info" && (
            <PlaybackInfo player={handle?.player ?? null} status={status} />
          )}
        </aside>
      </main>
      {toast && (
        <div className="toast" role="status">
          {toast}
        </div>
      )}
    </div>
  );
}
