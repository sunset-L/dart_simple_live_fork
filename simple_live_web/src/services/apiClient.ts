export async function request<T>(
  path: string,
  init: RequestInit = {},
  signal?: AbortSignal,
): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 90000);
  const forwardAbort = () => controller.abort();
  if (signal?.aborted) controller.abort();
  signal?.addEventListener("abort", forwardAbort, { once: true });
  try {
    const response = await fetch(`/api/${path}`, {
      ...init,
      signal: controller.signal,
      headers: { "X-Simple-Live": "web", ...(init.headers ?? {}) },
    });
    let body: unknown;
    try {
      body = await response.json();
    } catch {
      throw new Error("本地服务返回了无效数据");
    }
    if (!response.ok)
      throw new Error(
        typeof body === "object" && body !== null && "error" in body
          ? String(body.error)
          : `请求失败（${response.status}）`,
      );
    return body as T;
  } catch (error) {
    if (signal?.aborted) throw error;
    if (error instanceof DOMException && error.name === "AbortError")
      throw new Error("请求超时，请重试");
    throw error instanceof Error ? error : new Error("请求失败");
  } finally {
    clearTimeout(timeout);
    signal?.removeEventListener("abort", forwardAbort);
  }
}
export function get<T>(path: string, signal?: AbortSignal) {
  return request<T>(path, {}, signal);
}
export function post<T>(path: string, body: unknown, signal?: AbortSignal) {
  return request<T>(
    path,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    signal,
  );
}
export function api<T>(path: string, body?: unknown, signal?: AbortSignal) {
  return body === undefined
    ? get<T>(path, signal)
    : post<T>(path, body, signal);
}
