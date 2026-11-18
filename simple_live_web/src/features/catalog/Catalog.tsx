import { useEffect, useState } from "react";
import {
  ArrowLeft,
  Cloud,
  Compass,
  Heart,
  LoaderCircle,
  RefreshCw,
} from "lucide-react";
import { api } from "../../services/libraryData";
import {
  platforms,
  safeImage,
  type Category,
  type CategoryGroup,
  type Follow,
  type Room,
} from "../../services/libraryData";

export function Picture({
  src,
  className,
  alt = "",
}: {
  src?: string | null;
  className?: string;
  alt?: string;
}) {
  return (
    <img
      src={safeImage(src)}
      className={className}
      alt={alt}
      loading="lazy"
      referrerPolicy="no-referrer"
      onError={(event) => {
        if (!event.currentTarget.src.endsWith("/assets/logo.png"))
          event.currentTarget.src = "/assets/logo.png";
      }}
    />
  );
}
export function Empty({
  title,
  message,
  retry,
}: {
  title: string;
  message?: string;
  retry?: () => void;
}) {
  return (
    <div className="empty">
      <div className="empty-icon">
        {retry ? <Cloud size={28} /> : <Compass size={28} />}
      </div>
      <h2>{title}</h2>
      {message && <p>{message}</p>}
      {retry && (
        <button onClick={retry}>
          <RefreshCw size={16} />
          重试
        </button>
      )}
    </div>
  );
}
function Platforms({
  site,
  onChange,
}: {
  site: string;
  onChange: (site: string) => void;
}) {
  return (
    <div className="platform-tabs" role="tablist" aria-label="直播平台">
      {platforms.map((item) => (
        <button
          role="tab"
          aria-selected={site === item.id}
          key={item.id}
          className={site === item.id ? "active" : ""}
          onClick={() => onChange(item.id)}
        >
          <img src={`/assets/${item.logo}`} alt="" />
          {item.name}
        </button>
      ))}
    </div>
  );
}
interface Props {
  site: string;
  onSite: (site: string) => void;
  follows: Follow[];
  onFollow: (room: Room) => void;
  search: string;
  categories?: boolean;
  onOpenPlayback: (room: Room) => void;
}

export function Catalog({
  site,
  onSite,
  follows,
  onFollow,
  search,
  categories = false,
  onOpenPlayback,
}: Props) {
  const [category, setCategory] = useState<Category | null>(null);
  const [refresh, setRefresh] = useState(0);
  const [groups, setGroups] = useState<CategoryGroup[]>([]);
  const [groupsLoading, setGroupsLoading] = useState(false);
  const [groupsError, setGroupsError] = useState("");
  const showCategories = categories && !category && !search;
  const effectiveCategory = category;
  useEffect(() => {
    if (!showCategories) return;
    const controller = new AbortController();
    setGroupsLoading(true);
    setGroupsError("");
    setGroups([]);
    api<CategoryGroup[]>(
      `categories?${new URLSearchParams({ site })}`,
      undefined,
      controller.signal,
    )
      .then((value) => {
        if (!controller.signal.aborted) setGroups(value);
      })
      .catch((error) => {
        if (!controller.signal.aborted) setGroupsError(error.message);
      })
      .finally(() => {
        if (!controller.signal.aborted) setGroupsLoading(false);
      });
    return () => controller.abort();
  }, [site, showCategories, refresh]);
  const title = search
    ? `搜索：${search}`
    : (effectiveCategory?.name ?? (categories ? "全部分类" : "热门直播"));
  const params = new URLSearchParams({ site });
  if (search) params.set("q", search);
  else if (effectiveCategory) {
    params.set("category", effectiveCategory.id);
    params.set("parent", effectiveCategory.parentId);
  }
  const endpoint = `${search ? "search" : "rooms"}?${params}`;
  return (
    <div className="catalog-content">
      <Platforms
        site={site}
        onChange={(next) => {
          setCategory(null);
          onSite(next);
        }}
      />
      <div className="content-heading">
        <div className="heading-with-back">
          {category && (
            <button
              className="icon-button"
              title="返回分类"
              aria-label="返回分类"
              onClick={() => setCategory(null)}
            >
              <ArrowLeft size={20} />
            </button>
          )}
          <h1>{title}</h1>
        </div>
        <button
          className="icon-button"
          title="刷新"
          aria-label="刷新"
          onClick={() => setRefresh((value) => value + 1)}
        >
          <RefreshCw size={18} />
        </button>
      </div>
      {showCategories ? (
        groupsLoading ? (
          <Loading />
        ) : groupsError ? (
          <Empty
            title="分类加载失败"
            message={groupsError}
            retry={() => setRefresh((value) => value + 1)}
          />
        ) : groups.length ? (
          <div className="category-groups">
            {groups.map((group) => (
              <section key={group.id}>
                <h2>{group.name}</h2>
                <div className="category-grid">
                  {group.children.map((item) => (
                    <button
                      key={item.id}
                      className="category-card"
                      onClick={() => setCategory(item)}
                    >
                      <Picture src={item.pic} />
                      <span>{item.name}</span>
                    </button>
                  ))}
                </div>
              </section>
            ))}
          </div>
        ) : (
          <Empty title="暂无分类" />
        )
      ) : (
        <Rooms
          key={`${endpoint}:${refresh}`}
          endpoint={endpoint}
          follows={follows}
          onFollow={onFollow}
          onOpenPlayback={onOpenPlayback}
        />
      )}
    </div>
  );
}
function Loading() {
  return (
    <div className="loading" role="status">
      <LoaderCircle className="spin" size={28} />
      <span>正在加载</span>
    </div>
  );
}
function Rooms({
  endpoint,
  follows,
  onFollow,
  onOpenPlayback,
}: {
  endpoint: string;
  follows: Follow[];
  onFollow: (room: Room) => void;
  onOpenPlayback: (room: Room) => void;
}) {
  const [rooms, setRooms] = useState<Room[]>([]);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [retry, setRetry] = useState(0);
  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    setError("");
    api<{ items: Room[]; hasMore: boolean }>(
      `${endpoint}&page=${page}`,
      undefined,
      controller.signal,
    )
      .then((result) => {
        if (controller.signal.aborted) return;
        setRooms((previous) => [
          ...new Map(
            [...previous, ...result.items].map((room) => [
              `${room.siteId}_${room.roomId}`,
              room,
            ]),
          ).values(),
        ]);
        setHasMore(result.hasMore);
      })
      .catch((error) => {
        if (!controller.signal.aborted) setError(error.message);
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [endpoint, page, retry]);
  if (loading && !rooms.length) return <Loading />;
  return (
    <>
      <div className="room-grid">
        {rooms.map((room) => {
          const followed = follows.some(
            (user) => user.id === `${room.siteId}_${room.roomId}`,
          );
          return (
            <article
              className="room-card"
              key={`${room.siteId}_${room.roomId}`}
            >
              <button
                className="room-cover"
                onClick={() => onOpenPlayback(room)}
                aria-label={`打开 ${room.userName} 的直播间`}
              >
                <Picture src={room.cover} />
                <span className="live-dot">直播中</span>
                <span className="viewers">
                  {room.online.toLocaleString("zh-CN")} 人气
                </span>
              </button>
              <div className="room-body">
                <div className="room-text">
                  <strong title={room.title}>
                    {room.title || "未命名直播间"}
                  </strong>
                  <span>{room.userName}</span>
                </div>
                <button
                  className={`icon-button ${followed ? "followed" : ""}`}
                  title={followed ? "取消关注" : "添加关注"}
                  aria-label={`${followed ? "取消关注" : "关注"} ${room.userName}`}
                  aria-pressed={followed}
                  onClick={() => onFollow(room)}
                >
                  <Heart size={18} fill={followed ? "currentColor" : "none"} />
                </button>
              </div>
            </article>
          );
        })}
      </div>
      {error && (
        <Empty
          title="直播列表加载失败"
          message={error}
          retry={() => setRetry((value) => value + 1)}
        />
      )}
      {!error && !rooms.length && <Empty title="没有找到直播间" />}
      {hasMore && !error && (
        <div className="pagination">
          <button
            className="quiet-button"
            disabled={loading}
            onClick={() => {
              setLoading(true);
              setPage((value) => value + 1);
            }}
          >
            {loading && <LoaderCircle className="spin" size={16} />}
            {loading ? "正在加载" : "加载更多"}
          </button>
        </div>
      )}
    </>
  );
}
