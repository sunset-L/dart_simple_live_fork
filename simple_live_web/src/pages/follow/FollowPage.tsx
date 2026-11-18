import {
  History as HistoryIcon,
  Plus,
  RefreshCw,
  X,
} from "lucide-react";
import { Empty } from "../../features/catalog/Catalog";
import {
  type Library,
  type Follow,
} from "../../services/libraryData";
import { useFollowStatus } from "../../features/follow/useFollowStatus";
import { LiveCard } from "../../components/LiveCard";

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
  notify,
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
  notify: (message: string) => void;
}) {
  const tags = [...new Set(["全部", ...data.tags.map((item) => item.tag)])];
  const { statuses, loading, refresh } = useFollowStatus(data.follows);
  const liveCount = following.filter(
    (item) => statuses[item.id]?.status === true,
  ).length;
  const visible = following.filter((item) =>
    filter === "live" ? statuses[item.id]?.status === true
      : filter === "offline" ? statuses[item.id]?.status === false
        : true,
  );
  if (filter === "all")
    visible.sort((left, right) =>
      Number(statuses[right.id]?.status === true) -
      Number(statuses[left.id]?.status === true),
    );
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
            disabled={loading || !data.follows.length}
            onClick={() =>
              refresh(({ total, failed }) =>
                notify(
                  failed === 0
                    ? "刷新成功"
                    : failed === total
                      ? "刷新失败，请稍后重试"
                      : `刷新完成，${failed} 位主播查询失败，请稍后重试`,
                ),
              )
            }
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
        <div className="tabs" aria-label="开播状态筛选">
          {[
            ["all", "全部"],
            ["live", "直播中"],
            ["offline", "未开播"],
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
        {data.tags.length > 0 && (
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
        )}
      </div>
      {visible.length ? (
        <div className="live-card-grid">
          {visible.map((item) => {
            const state = statuses[item.id];
            return (
              <LiveCard
                key={item.id}
                {...item}
                face={state?.face || item.face}
                cover={state?.cover}
                title={state?.title}
                online={state?.online}
                status={state?.status}
                statusError={state?.error}
                followed={true}
                onEdit={() => onEdit(item)}
                onFollow={() => {
                  if (confirm(`取消关注 ${item.userName}？`)) onFollow(item);
                }}
              />
            );
          })}
        </div>
      ) : loading && following.length && filter !== "all" ? (
        <div className="loading" role="status">正在查询开播状态</div>
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
