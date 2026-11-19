import { useEffect, useState } from "react";
import { Button, Spin, Tabs, Tooltip } from "antd";
import { ArrowLeft, Cloud, Compass, RefreshCw } from "lucide-react";
import { api } from "../../services/libraryData";
import {
  platforms,
  type Category,
  type CategoryGroup,
  type Follow,
  type Room,
} from "../../services/libraryData";
import { LiveCard } from "../../components/LiveCard";
import { Picture } from "../../components/Picture";
import {
  scrollLoadTriggerStyle,
  useScrollLoadMore,
} from "../../hooks/useScrollLoadMore";
export { Picture } from "../../components/Picture";
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
        <Button type="primary" onClick={retry} icon={<RefreshCw size={16} />}>
          重试
        </Button>
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
    <Tabs
      className="platform-tabs"
      aria-label="直播平台"
      activeKey={site}
      onChange={onChange}
      items={platforms.map((item) => ({
        key: item.id,
        label: (
          <span className="platform-tab-label">
            <img src={`/assets/${item.logo}`} alt="" />
            {item.name}
          </span>
        ),
      }))}
    />
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
            <Tooltip title="返回分类">
              <Button
                type="text"
                aria-label="返回分类"
                onClick={() => setCategory(null)}
                icon={<ArrowLeft size={20} />}
              />
            </Tooltip>
          )}
          <h1>{title}</h1>
        </div>
        <Tooltip title="刷新">
          <Button
            type="text"
            aria-label="刷新"
            onClick={() => setRefresh((value) => value + 1)}
            icon={<RefreshCw size={18} />}
          />
        </Tooltip>
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
      <Spin />
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
  const loadMoreRef = useScrollLoadMore({
    hasMore: hasMore && !error,
    loading,
    onLoad: () => setPage((value) => value + 1),
  });
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
      <div className="live-card-grid">
        {rooms.map((room) => {
          const followed = follows.find(
            (user) => user.id === `${room.siteId}_${room.roomId}`,
          );
          return (
            <LiveCard
              key={`${room.siteId}_${room.roomId}`}
              {...room}
              face={followed?.face}
              followed={Boolean(followed)}
              status={true}
              showPlatform={false}
              onFollow={() => onFollow(room)}
              onOpen={() => onOpenPlayback(room)}
            />
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
        <div
          ref={loadMoreRef}
          className="pagination"
          style={scrollLoadTriggerStyle}
          aria-live="polite"
        >
          {loading && (
            <>
              <Spin size="small" />
              <span>正在加载</span>
            </>
          )}
        </div>
      )}
    </>
  );
}
