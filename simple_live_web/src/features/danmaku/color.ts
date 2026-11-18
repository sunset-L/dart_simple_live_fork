export function normalizeDanmakuColor(value: unknown) {
  if (typeof value !== "string") return "#ffffff";
  const color = value.trim();
  if (/^#[0-9a-f]{6}$/i.test(color)) return color;
  if (/^#[0-9a-f]{3}$/i.test(color))
    return `#${[...color.slice(1)].map((part) => part.repeat(2)).join("")}`;
  return "#ffffff";
}

export function displayDanmakuColor(
  original: string,
  mode: string,
  custom: string,
) {
  return mode === "white"
    ? "#ffffff"
    : normalizeDanmakuColor(mode === "custom" ? custom : original);
}
