import {
  History as HistoryIcon,
  Plus,
  RefreshCw,
  Settings,
  Trash2,
  X,
} from "lucide-react";
import { Picture, Empty } from "../../features/catalog/Catalog";
import {
  platforms,
  type Library,
  type Follow,
} from "../../services/libraryData";
import { openPlayback } from "../../app/routes";
import { useFollowStatus } from "../../features/follow/useFollowStatus";
import { FollowStatusLabel } from "../../features/follow/FollowStatusLabel";

export function FollowPage({
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
  const { statuses, loading, refresh } = useFollowStatus(following);
  const liveCount = following.filter(
    (item) => statuses[item.id]?.status === true,
  ).length;
  return (
    <div className="follow-content">
      <div className="content-heading">
        <div>
          <h1>我的关注</h1>
          <span className="muted">
            {following.length} 位主播 · {liveCount} 位直播中
          </span>
        </div>
        <div className="actions compact">
          <button
            title="刷新开播状态"
            aria-label="刷新开播状态"
            disabled={loading || !following.length}
            onClick={refresh}
          >
            <RefreshCw size={18} className={loading ? "spin" : ""} />
          </button>
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
                <button
                  className="room-link"
                  onClick={() => openPlayback(item.siteId, item.roomId)}
                >
                  {item.userName}
                </button>
                <span>
                  {platforms.find((platform) => platform.id === item.siteId)
                    ?.name ?? item.siteId}{" "}
                  · {item.tag}
                </span>
                <small>房间 {item.roomId}</small>
                <FollowStatusLabel value={statuses[item.id]} />
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
