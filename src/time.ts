/** Clock time as HH:MM:SS. Sub-second input is floored. */
export function formatHms(seconds: number): string {
  const s = Math.max(0, Math.floor(Number.isFinite(seconds) ? seconds : 0));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  return [h, m, sec].map((n) => String(n).padStart(2, "0")).join(":");
}

export function round3(seconds: number): number {
  return Math.round(seconds * 1000) / 1000;
}
