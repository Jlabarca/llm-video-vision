/** Mean absolute difference per byte. 0 means identical. */
export function meanAbsDiff(a: Uint8Array, b: Uint8Array): number {
  const n = Math.min(a.length, b.length);
  if (n === 0) return Number.POSITIVE_INFINITY;
  let sum = 0;
  for (let i = 0; i < n; i++) sum += Math.abs(a[i] - b[i]);
  return sum / n;
}

export interface ThumbFrame {
  pixels?: Uint8Array;
}

/**
 * Drop a frame when it is within `threshold` of an already kept frame.
 * Order is time order. The first frame of a near-duplicate run survives,
 * which is what a slide deck wants: one image per visual, not one per sample.
 */
export function dropNearDuplicates<T extends ThumbFrame>(frames: T[], threshold = 12): T[] {
  const kept: T[] = [];
  for (const frame of frames) {
    if (!frame.pixels || frame.pixels.length === 0) {
      kept.push(frame);
      continue;
    }
    const duplicate = kept.some(
      (prev) => prev.pixels && meanAbsDiff(prev.pixels, frame.pixels!) < threshold,
    );
    if (!duplicate) kept.push(frame);
  }
  return kept;
}
