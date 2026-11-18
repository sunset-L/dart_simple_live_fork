import { Trash2, Heart } from "lucide-react";
import { Picture, Empty } from "../../features/catalog/Catalog";
import {
  platforms,
  type Library,
  type History,
} from "../../services/libraryData";
import { openPlayback } from "../../app/routes";

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
  return (
    <div className="follow-content">
      <div className="content-heading">
        <h1>历史记录</h1>
        {data.histories.length > 0 && (
          <button className="quiet-button danger-text" onClick={onClear}>
            <Trash2 size={17} />
            清空
          </button>
        )}
      </div>
      {data.histories.length ? (
        <div className="follow-grid">
          {[...data.histories]
            .sort((a, b) => Date.parse(b.updateTime) - Date.parse(a.updateTime))
            .map((item) => {
              const followed = data.follows.some((user) => user.id === item.id);
              return (
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
                        ?.name ?? item.siteId}
                    </span>
                    <small>
                      {new Date(item.updateTime).toLocaleString("zh-CN")}
                    </small>
                  </div>
                  <button
                    title={followed ? "取消关注" : "添加关注"}
                    aria-label={followed ? "取消关注" : "添加关注"}
                    onClick={() => onFollow(item)}
                  >
                    <Heart
                      size={16}
                      fill={followed ? "currentColor" : "none"}
                    />
                  </button>
                  <button
                    title="删除记录"
                    aria-label="删除记录"
                    onClick={() => onRemove(item.id)}
                  >
                    <Trash2 size={16} />
                  </button>
                </article>
              );
            })}
        </div>
      ) : (
        <Empty title="暂无历史记录" />
      )}
    </div>
  );
}
