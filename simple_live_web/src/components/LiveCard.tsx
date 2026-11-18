import { useEffect, useRef, useState } from "react";
import { App as AntApp, Button, Tooltip } from "antd";
import { Clock3, Flame, Heart, Settings, Trash2 } from "lucide-react";
import { platforms } from "../app/platforms";
import { openPlayback } from "../app/routes";
import { Picture } from "./Picture";
import { safeImage } from "../services/media";
import { readCardProfile, needsFollowAvatar } from "../features/follow/profile";
import { formatHeat } from "./formatHeat";

export function LiveCard({
  siteId,
  roomId,
  userName,
  title,
  cover,
  face = "",
  online,
  status,
  statusError,
  showPlatform = true,
  tag,
  time,
  followed,
  onFollow,
  onEdit,
  onRemove,
  onOpen,
}: {
  siteId: string;
  roomId: string;
  userName: string;
  title?: string;
  cover?: string;
  face?: string;
  online?: number;
  status?: boolean | null;
  statusError?: string;
  showPlatform?: boolean;
  tag?: string;
  time?: string;
  followed: boolean;
  onFollow: () => void;
  onEdit?: () => void;
  onRemove?: () => void;
  onOpen?: () => void;
}) {
  const { modal } = AntApp.useApp();
  const followAction = useRef({ followed, onFollow });
  followAction.current = { followed, onFollow };
  const platform = platforms.find((item) => item.id === siteId);
  const card = useRef<HTMLElement>(null);
  const [avatar, setAvatar] = useState("");
  const [failedAvatar, setFailedAvatar] = useState("");
  const [failedCover, setFailedCover] = useState("");
  useEffect(() => {
    setAvatar("");
    if (!needsFollowAvatar(face) || !card.current) return;
    let canceled = false;
    const observer = new IntersectionObserver(
      (entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return;
        observer.disconnect();
        void readCardProfile(siteId, roomId)
          .then((profile) => {
            if (!canceled && profile.face) setAvatar(profile.face);
          })
          .catch(() => {
            /* Leave the avatar hidden when the platform cannot provide one. */
          });
      },
      { rootMargin: "100px" },
    );
    observer.observe(card.current);
    return () => {
      canceled = true;
      observer.disconnect();
    };
  }, [siteId, roomId, face]);

  const avatarUrl = needsFollowAvatar(face) ? avatar : face;
  const state =
    status === false
      ? "未开播"
      : status === null
        ? "查询失败"
        : status === undefined
          ? "查询中"
          : "";
  return (
    <article
      className={`live-card ${status === false ? "is-offline" : ""}`}
      ref={card}
    >
      <button
        className="live-card-open"
        disabled={status === false}
        aria-label={
          status === false ? `${userName} 未开播` : `进入 ${userName} 的直播间`
        }
        title={
          status === false ? "主播未开播" : statusError || title || userName
        }
        onClick={() => {
          if (status !== false)
            (onOpen ?? (() => openPlayback(siteId, roomId)))();
        }}
      />
      <div
        className={`live-card-cover ${status === false ? "is-offline" : ""}`}
      >
        {safeImage(cover) !== "/assets/logo.png" && failedCover !== cover && (
          <Picture
            src={cover}
            className="live-card-image"
            onError={() => setFailedCover(cover ?? "")}
          />
        )}
        {state && (
          <div className="live-card-state" title={statusError ?? state}>
            <span>
              <Clock3 size={16} />
              {state}
            </span>
          </div>
        )}
        <div className="live-card-overlay">
          <div className="live-card-anchor">
            {!needsFollowAvatar(avatarUrl) && failedAvatar !== avatarUrl && (
              <Picture
                src={avatarUrl}
                onError={() => setFailedAvatar(avatarUrl)}
              />
            )}
            <span>{userName}</span>
          </div>
          {status === true &&
            online !== undefined &&
            Number.isFinite(online) &&
            online >= 0 && (
              <span
                className="live-card-heat"
                title={`热度 ${formatHeat(online)}`}
              >
                <Flame size={16} />
                {formatHeat(online)}
              </span>
            )}
        </div>
      </div>
      <div className="live-card-body">
        <div className="live-card-heading">
          <strong title={title || userName}>{title || userName}</strong>
          {onEdit && (
            <Tooltip title="设置标签">
              <Button
                type="text"
                className="live-card-action"
                aria-label={`设置 ${userName} 的标签`}
                onClick={onEdit}
                icon={<Settings size={17} />}
              />
            </Tooltip>
          )}
          <Tooltip title={followed ? "取消关注" : "添加关注"}>
            <Button
              type="text"
              className={`live-card-action ${followed ? "followed" : ""}`}
              aria-label={`${followed ? "取消关注" : "关注"} ${userName}`}
              aria-pressed={followed}
              onClick={() => {
                if (!followed) {
                  onFollow();
                  return;
                }
                modal.confirm({
                  title: `取消关注 ${userName}？`,
                  onOk: () => {
                    if (card.current && followAction.current.followed)
                      followAction.current.onFollow();
                  },
                });
              }}
              icon={
                <Heart size={18} fill={followed ? "currentColor" : "none"} />
              }
            />
          </Tooltip>
          {onRemove && (
            <Tooltip title="删除记录">
              <Button
                type="text"
                className="live-card-action"
                aria-label={`删除 ${userName} 的历史记录`}
                onClick={onRemove}
                icon={<Trash2 size={17} />}
              />
            </Tooltip>
          )}
        </div>
        {(showPlatform || (tag && tag !== "全部") || time) && (
          <div className="live-card-meta">
            {showPlatform && (
              <span className="live-card-platform">
                {platform && <img src={`/assets/${platform.logo}`} alt="" />}
                {platform?.name ?? siteId}
              </span>
            )}
            {tag && tag !== "全部" && (
              <span className="live-card-tag">{tag}</span>
            )}
            {time && (
              <time dateTime={time} title="观看时间">
                {new Date(time).toLocaleString("zh-CN")}
              </time>
            )}
          </div>
        )}
      </div>
    </article>
  );
}
