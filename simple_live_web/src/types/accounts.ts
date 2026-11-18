export const accountSites = ["bilibili", "douyu", "douyin"] as const;
export type AccountSite = (typeof accountSites)[number];
export type AccountCredentials = Partial<Record<AccountSite, string>>;
export interface AccountItem {
  site: AccountSite | "huya";
  configured: boolean;
  state: "empty" | "default" | "saved" | "valid" | "invalid" | "unknown";
  name?: string;
  message?: string;
}
export interface AccountSummary {
  revision: string;
  items: AccountItem[];
}
export interface QrSession {
  sessionId: string;
  url: string;
  expiresAt: number;
}
export interface QrResult {
  state: "waiting" | "scanned" | "expired" | "success";
  accounts?: AccountSummary;
}
