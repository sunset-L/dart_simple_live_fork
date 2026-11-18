import { History as HistoryIcon, Plus, RefreshCw, X } from "lucide-react";
import { Button, Popconfirm, Segmented, Tag, Tooltip } from "antd";
import { Empty } from "../../features/catalog/Catalog";
import { type Library, type Follow } from "../../services/libraryData";
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
  const customTags = data.tags.filter((item) => item.tag !== "全部");
  const tags = [...new Set(["全部", ...customTags.map((item) => item.tag)])];
  const { statuses, loading, refresh } = useFollowStatus(data.follows);
  const liveCount = following.filter(
    (item) => statuses[item.id]?.status === true,
  ).length;
  const visible = following.filter((item) =>
    filter === "live"
      ? statuses[item.id]?.status === true
      : filter === "offline"
        ? statuses[item.id]?.status === false
        : true,
  );
  if (filter === "all")
    visible.sort(
      (left, right) =>
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
          <Tooltip title="刷新开播状态">
            <Button
              aria-label="刷新开播状态"
              disabled={loading || !data.follows.length}
              icon={<RefreshCw size={18} className={loading ? "spin" : ""} />}
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
            />
          </Tooltip>
          <Tooltip title="历史记录">
            <Button
              aria-label="历史记录"
              icon={<HistoryIcon size={18} />}
              onClick={onHistory}
            />
          </Tooltip>
          <Button type="primary" icon={<Plus size={17} />} onClick={onAdd}>
            添加关注
          </Button>
        </div>
      </div>
      <div className="filter-bar">
        <Segmented
          aria-label="开播状态筛选"
          value={filter}
          onChange={setFilter}
          options={[
            { value: "all", label: "全部" },
            { value: "live", label: "直播中" },
            { value: "offline", label: "未开播" },
          ]}
        />
        {customTags.length > 0 && (
          <div className="tag-list">
            {tags.map((item) => (
              <Tag.CheckableTag
                key={item}
                checked={tag === item}
                onChange={() => setTag(item)}
              >
                {item}
              </Tag.CheckableTag>
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
                onFollow={() => onFollow(item)}
              />
            );
          })}
        </div>
      ) : loading && following.length && filter !== "all" ? (
        <div className="loading" role="status">
          正在查询开播状态
        </div>
      ) : (
        <Empty
          title={data.follows.length ? "没有符合条件的关注" : "暂无关注"}
        />
      )}
      {customTags.length > 0 && (
        <div className="tag-manage">
          <span>标签</span>
          {customTags.map((item) => (
            <Popconfirm
              key={item.id}
              title={`删除标签“${item.tag}”？`}
              description="主播不会被取消关注"
              onConfirm={() => onRemoveTag(item.tag)}
            >
              <Button
                size="small"
                icon={<X size={14} />}
                title={`删除标签 ${item.tag}`}
              >
                {item.tag}
              </Button>
            </Popconfirm>
          ))}
        </div>
      )}
    </div>
  );
}
