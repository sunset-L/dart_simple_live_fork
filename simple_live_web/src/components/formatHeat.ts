export function formatHeat(value: number): string {
  const heat = Number.isFinite(value) ? Math.max(0, value) : 0;
  const options = { maximumFractionDigits: 1 };
  if (heat >= 100000000)
    return `${(heat / 100000000).toLocaleString("zh-CN", options)}亿`;
  if (heat >= 10000)
    return `${(heat / 10000).toLocaleString("zh-CN", options)}万`;
  return heat.toLocaleString("zh-CN");
}
