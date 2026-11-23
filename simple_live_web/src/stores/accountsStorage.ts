import { useEffect, useSyncExternalStore } from "react";
import { get, post } from "../services/apiClient";
import type {
  AccountCredentials,
  AccountSite,
  AccountSummary,
  QrResult,
  QrSession,
} from "../types/accounts";

const listeners = new Set<() => void>();
let cached = { data: null as AccountSummary | null, error: "" };
let generation = 0;
let mutating = 0;
let refreshing: Promise<AccountSummary> | undefined;

export function acceptAccounts(data: AccountSummary) {
  generation++;
  cached = { data, error: "" };
  listeners.forEach((listener) => listener());
}
export function refreshAccounts(): Promise<AccountSummary> {
  if (refreshing) return refreshing;
  const started = generation;
  refreshing = get<AccountSummary>("accounts")
    .then((data) => {
      if (started === generation && !mutating) acceptAccounts(data);
      return cached.data ?? data;
    })
    .catch((error: unknown) => {
      if (started === generation && !mutating) {
        cached = {
          ...cached,
          error: error instanceof Error ? error.message : "账号读取失败",
        };
        listeners.forEach((listener) => listener());
      }
      throw error;
    })
    .finally(() => {
      refreshing = undefined;
    });
  return refreshing;
}
function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}
export function useAccounts(enabled = true) {
  const result = useSyncExternalStore(subscribe, () => cached);
  useEffect(() => {
    if (!enabled) return;
    const refresh = () => void refreshAccounts().catch(() => {});
    // 直播页可能在另一标签页标记授权失效，返回账号页时读取最新状态。
    refresh();
    window.addEventListener("focus", refresh);
    return () => window.removeEventListener("focus", refresh);
  }, [enabled]);
  return result;
}
export async function updateAccount(
  action: "save" | "clear" | "check",
  site: AccountSite,
  revision: string,
  credential?: string,
) {
  await mutateAccounts({ action, site, revision, credential });
}
export async function restoreAccounts(data: AccountCredentials, revision: string) {
  await mutateAccounts({ action: "restore", data, revision });
}
async function mutateAccounts(body: unknown) {
  const started = ++generation;
  mutating++;
  try {
    const data = await post<AccountSummary>("accounts", body);
    if (started === generation) acceptAccounts(data);
  } finally {
    mutating--;
  }
}
export function validateAccounts(data: AccountCredentials) {
  return post("accounts", { action: "validate", data });
}
export async function exportAccounts(sites: AccountSite[], revision: string) {
  return (await post<{ data: AccountCredentials }>("accounts", {
    action: "export", sites, revision,
  })).data;
}
export const qrLogin = {
  generate: (revision: string, signal: AbortSignal) =>
    post<QrSession>("accounts", { action: "qr-generate", revision }, signal),
  poll: (sessionId: string, signal: AbortSignal) =>
    post<QrResult>("accounts", { action: "qr-poll", sessionId }, signal),
  cancel: (sessionId: string) =>
    post("accounts", { action: "qr-cancel", sessionId }),
};
