import { CircleAlert, LoaderCircle, Radio } from "lucide-react";
import type { FollowStatus } from "./useFollowStatus";

export function FollowStatusLabel({ value }: { value?: FollowStatus }) {
  const label = !value
    ? "查询中"
    : value.status === true
      ? "直播中"
      : value.status === false
        ? "未开播"
        : "查询失败";
  return (
    <span
      className={`follow-status ${value?.status === true ? "is-live" : ""} ${value?.error ? "is-error" : ""}`}
      title={value?.error ?? label}
    >
      {!value ? (
        <LoaderCircle size={12} className="spin" />
      ) : value.error ? (
        <CircleAlert size={12} />
      ) : (
        <Radio size={12} />
      )}
      {label}
    </span>
  );
}
