export function safeImage(value: string | null | undefined): string {
  if (!value) return "/assets/logo.png";
  try {
    const url = new URL(value.startsWith("//") ? `https:${value}` : value);
    return ["http:", "https:"].includes(url.protocol)
      ? url.href
      : "/assets/logo.png";
  } catch {
    return "/assets/logo.png";
  }
}
