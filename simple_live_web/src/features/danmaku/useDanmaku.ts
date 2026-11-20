import { useCallback, useEffect, useRef, useState } from "react";
import { playbackApi } from "../../services/playbackApi";
import type { DanmakuMessage, DanmakuStatus } from "../../types/playback";
import { normalizeDanmakuColor } from "./color";

export function useDanmaku(
  site: string,
  room: string,
  enabled: boolean,
  paused = false,
) {
  const [messages, setMessages] = useState<DanmakuMessage[]>([]);
  const [status, setStatus] = useState<DanmakuStatus>("closed");
  const [online, setOnline] = useState<number | null>(null);
  const [revision, setRevision] = useState(0);
  const serial = useRef(0);
  useEffect(() => {
    setMessages([]);
    setOnline(null);
  }, [site, room, enabled, revision]);
  useEffect(() => {
    // Suspend only the connection; keep received messages when pausing/resuming.
    if (!enabled || paused) {
      setStatus("closed");
      return;
    }
    let stopped = false,
      retry = 0;
    let socket: WebSocket | null = null;
    let timer: ReturnType<typeof setTimeout>;
    const connect = () => {
      setStatus(retry ? "reconnecting" : "connecting");
      socket = new WebSocket(playbackApi.danmakuUrl(site, room));
      socket.onmessage = (event) => {
        if (stopped) return;
        try {
          const value = JSON.parse(event.data);
          const batch =
            value.type === "batch" && Array.isArray(value.events)
              ? value.events
              : [value];
          const chats: DanmakuMessage[] = [];
          for (const item of batch) {
            if (item.type === "status") {
              setStatus(item.status);
              if (item.status === "ready") retry = 0;
            } else if (item.type === "online" && Number.isFinite(item.online))
              setOnline(item.online);
            else if (
              ["chat", "superChat"].includes(item.type) &&
              typeof item.message === "string" &&
              typeof item.userName === "string"
            )
              chats.push({
                ...item,
                color: normalizeDanmakuColor(item.color),
                id: ++serial.current,
              });
          }
          if (chats.length)
            setMessages((previous) => [...previous, ...chats].slice(-300));
        } catch {
          /* Ignore invalid messages without interrupting video playback. */
        }
      };
      socket.onclose = (event) => {
        if (stopped) return;
        if (event.code === 1000 || retry >= 5) {
          setStatus(event.code === 1000 ? "closed" : "error");
          return;
        }
        setStatus("reconnecting");
        timer = setTimeout(connect, Math.min(1000 * 2 ** retry++, 15000));
      };
      socket.onerror = () => {
        if (!stopped) setStatus("error");
      };
    };
    connect();
    return () => {
      stopped = true;
      clearTimeout(timer);
      socket?.close();
    };
  }, [site, room, enabled, paused, revision]);
  return {
    messages,
    status,
    online,
    reconnect: useCallback(() => setRevision((value) => value + 1), []),
  };
}
