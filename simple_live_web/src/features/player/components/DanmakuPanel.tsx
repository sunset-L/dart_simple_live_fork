import { RefreshCw, Wifi, WifiOff } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import type { DanmakuMessage, DanmakuStatus } from "../../../types/playback";
export function DanmakuPanel({
  messages,
  status,
  onReconnect,
}: {
  messages: DanmakuMessage[];
  status: DanmakuStatus;
  onReconnect: () => void;
}) {
  const list = useRef<HTMLDivElement>(null);
  const [follow, setFollow] = useState(true);
  useEffect(() => {
    if (follow && list.current)
      list.current.scrollTop = list.current.scrollHeight;
  }, [messages, follow]);
  return (
    <section className="danmaku-panel">
      <div className="panel-heading">
        <div>
          <strong>聊天</strong>
          <span className={`connection ${status}`}>
            {status === "ready" ? <Wifi size={14} /> : <WifiOff size={14} />}
            {status === "ready"
              ? "已连接"
              : status === "reconnecting"
                ? "重连中"
                : "未连接"}
          </span>
        </div>
        <button
          className="icon-button"
          title="重连弹幕"
          aria-label="重连弹幕"
          onClick={onReconnect}
        >
          <RefreshCw size={16} />
        </button>
      </div>
      <div
        ref={list}
        className="chat-list"
        onScroll={() => {
          const node = list.current;
          if (node)
            setFollow(
              node.scrollHeight - node.scrollTop - node.clientHeight < 50,
            );
        }}
      >
        {messages.length ? (
          messages.map((message) => (
            <div className="chat-line" key={message.id}>
              <strong style={{ color: message.color }}>
                {message.userName}
              </strong>
              <span>{message.message}</span>
            </div>
          ))
        ) : (
          <div className="muted chat-empty">暂无弹幕</div>
        )}
      </div>
      {!follow && (
        <button className="quiet-button" onClick={() => setFollow(true)}>
          回到最新
        </button>
      )}
    </section>
  );
}
