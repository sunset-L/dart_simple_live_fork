import { Trash2 } from "lucide-react";
import { useEffect, useState } from "react";
import { Button, Popconfirm } from "antd";
import { Empty } from "../../features/catalog/Catalog";
import { type Library, type History } from "../../services/libraryData";
import { LiveCard } from "../../components/LiveCard";
import { useFollowStatus } from "../../features/follow/useFollowStatus";
import {
  scrollLoadTriggerStyle,
  useScrollLoadMore,
} from "../../hooks/useScrollLoadMore";

export function HistoryPage({
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
  const history = [...data.histories].sort(
    (left, right) => Date.parse(right.updateTime) - Date.parse(left.updateTime),
  );
  const [visibleCount, setVisibleCount] = useState(20);
  useEffect(() => setVisibleCount(20), [data.histories.length]);
  const visibleHistory = history.slice(0, visibleCount);
  const { statuses, loading } = useFollowStatus(visibleHistory, true, true);
  const loadMoreRef = useScrollLoadMore({
    hasMore: visibleCount < history.length,
    loading,
    onLoad: () =>
      setVisibleCount((value) => Math.min(value + 20, history.length)),
  });
  return (
    <div className="follow-content">
      <div className="content-heading">
        <h1>历史记录</h1>
        {data.histories.length > 0 && (
          <Popconfirm title="清空全部历史记录？" onConfirm={onClear}>
            <Button danger icon={<Trash2 size={17} />}>
              清空
            </Button>
          </Popconfirm>
        )}
      </div>
      {data.histories.length ? (
        <div className="live-card-grid">
          {visibleHistory.map((item) => {
            const followed = data.follows.some((user) => user.id === item.id);
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
                time={item.updateTime}
                followed={followed}
                onFollow={() => onFollow(item)}
                onRemove={() => onRemove(item.id)}
              />
            );
          })}
        </div>
      ) : (
        <Empty title="暂无历史记录" />
      )}
      {visibleCount < history.length && (
        <div
          ref={loadMoreRef}
          className="pagination"
          style={scrollLoadTriggerStyle}
          aria-live="polite"
        >
          {loading && <span>正在加载</span>}
        </div>
      )}
    </div>
  );
}
