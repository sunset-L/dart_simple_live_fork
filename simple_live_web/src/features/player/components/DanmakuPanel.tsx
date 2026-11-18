import { RefreshCw, Wifi, WifiOff } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Button, Tooltip } from "antd";
import type { DanmakuMessage, DanmakuStatus } from "../../../types/playback";
import { normalizeDanmakuColor } from "../../danmaku/color";
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
        <Tooltip title="重连弹幕">
          <Button
            type="text"
            aria-label="重连弹幕"
            onClick={onReconnect}
            icon={<RefreshCw size={16} />}
          />
        </Tooltip>
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
              <strong title={message.userName}>{message.userName}:</strong>
              <span style={{ color: normalizeDanmakuColor(message.color) }}>
                {message.message}
              </span>
            </div>
          ))
        ) : (
          <div className="muted chat-empty">暂无弹幕</div>
        )}
      </div>
      {!follow && (
        <Button type="text" onClick={() => setFollow(true)}>
          回到最新
        </Button>
      )}
    </section>
  );
}
