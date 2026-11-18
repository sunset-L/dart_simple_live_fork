import { Trash2 } from "lucide-react";
import { Button, Popconfirm } from "antd";
import { Empty } from "../../features/catalog/Catalog";
import { type Library, type History } from "../../services/libraryData";
import { LiveCard } from "../../components/LiveCard";
import { useFollowStatus } from "../../features/follow/useFollowStatus";

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
  const { statuses } = useFollowStatus(data.histories);
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
          {[...data.histories]
            .sort((a, b) => Date.parse(b.updateTime) - Date.parse(a.updateTime))
            .map((item) => {
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
    </div>
  );
}
