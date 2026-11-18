export type PlaybackFormat = "hls" | "flv" | "native" | "unknown";
export type DanmakuStatus =
  "connecting" | "ready" | "reconnecting" | "closed" | "error";

export interface RoomDetail {
  roomId: string;
  siteId: string;
  title: string;
  cover: string;
  userName: string;
  userAvatar: string;
  online: number;
  status: boolean;
  url: string;
  introduction?: string | null;
  notice?: string | null;
}
export interface Quality {
  index: number;
  quality: string;
  sort: number;
}
export interface Source {
  index: number;
  url: string;
  proxyUrl: string;
  expiresAt?: number | null;
  format: PlaybackFormat;
  direct: boolean;
}
export interface DanmakuMessage {
  id?: number;
  type: "chat" | "online" | "superChat" | "gift";
  userName: string;
  message: string;
  color: string;
  online?: number;
  price?: number;
  endTime?: number;
  timestamp: number;
}
export interface DanmakuStatusMessage {
  type: "status";
  status: DanmakuStatus;
  message?: string;
}
export type DanmakuEvent = DanmakuMessage | DanmakuStatusMessage;
