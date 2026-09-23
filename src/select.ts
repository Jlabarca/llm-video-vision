import { round3 } from "./time.js";

export interface SceneHit {
  time: number;
  score: number;
}

export type FrameReason = "priority" | "scene" | "edge" | "floor";

export interface PickedFrame {
  time: number;
  reason: FrameReason;
  score: number;
}

export interface SelectInput {
  duration: number;
  scenes?: SceneHit[];
  /** Images the caller is willing to pay for. Clamped to 1..12. */
  budget?: number;
  /** At least one candidate every N seconds before thinning. */
  floorSeconds?: number;
  minSceneScore?: number;
  /** Drop the weaker frame when two land inside this window. */
  mergeSeconds?: number;
  priorityTimes?: number[];
}

export const FRAME_BUDGET_CAP = 12;

const REASON_RANK: Record<FrameReason, number> = {
  priority: 4,
  scene: 3,
  edge: 2,
  floor: 1,
};

export function clampBudget(budget: number | undefined): number {
  const n = budget == null || !Number.isFinite(budget) ? 9 : Math.floor(budget);
  return Math.min(FRAME_BUDGET_CAP, Math.max(1, n));
}

/**
 * Pick timestamps that cover the whole file inside a fixed image budget.
 * Candidates are edges, high-score cuts, question hits, and a density floor.
 * Anything over the budget is thinned by farthest-point sampling so the
 * first minutes are not the only minutes the model sees.
 */
export function selectFrames(input: SelectInput): PickedFrame[] {
  const duration = Math.max(0, input.duration);
  if (duration <= 0) return [];

  const budget = clampBudget(input.budget);
  const floor = input.floorSeconds ?? 30;
  const minScore = input.minSceneScore ?? 10;
  const merge = input.mergeSeconds ?? 0.75;
  const candidates: PickedFrame[] = [];

  const push = (time: number, reason: FrameReason, score: number) => {
    const t = Math.min(Math.max(0, time), Math.max(0, duration - 0.05));
    candidates.push({ time: round3(t), reason, score });
  };

  push(0, "edge", 1);
  if (duration > 1) push(duration - 0.25, "edge", 1);

  for (const p of input.priorityTimes ?? []) {
    if (p >= 0 && p <= duration) push(p, "priority", 100);
  }

  for (const scene of input.scenes ?? []) {
    if (scene.score >= minScore && scene.time >= 0 && scene.time <= duration) {
      push(scene.time, "scene", scene.score);
    }
  }

  if (floor > 0) {
    for (let t = floor; t < duration - floor / 2; t += floor) {
      push(t, "floor", 0.4);
    }
  }

  const merged = mergeClose(candidates, merge);
  const thinned = merged.length > budget ? thinToBudget(merged, budget) : merged;
  return thinned.sort((a, b) => a.time - b.time);
}

export function mergeClose(frames: PickedFrame[], windowSec: number): PickedFrame[] {
  const sorted = [...frames].sort(
    (a, b) => a.time - b.time || REASON_RANK[b.reason] - REASON_RANK[a.reason],
  );
  const out: PickedFrame[] = [];
  for (const frame of sorted) {
    const last = out[out.length - 1];
    if (last && Math.abs(frame.time - last.time) <= windowSec) {
      const better =
        frame.score > last.score ||
        (frame.score === last.score && REASON_RANK[frame.reason] > REASON_RANK[last.reason]);
      if (better) out[out.length - 1] = frame;
      continue;
    }
    out.push(frame);
  }
  return out;
}

export function thinToBudget(frames: PickedFrame[], budget: number): PickedFrame[] {
  if (frames.length <= budget) return [...frames].sort((a, b) => a.time - b.time);
  const sorted = [...frames].sort((a, b) => a.time - b.time);
  const kept = new Set<number>();

  sorted.forEach((frame, index) => {
    if (frame.reason === "priority" && kept.size < budget) kept.add(index);
  });
  if (kept.size < budget) kept.add(0);
  if (kept.size < budget) kept.add(sorted.length - 1);

  while (kept.size < budget) {
    let best = -1;
    let bestDist = -1;
    let bestScore = -Infinity;
    for (let i = 0; i < sorted.length; i++) {
      if (kept.has(i)) continue;
      let dist = Infinity;
      for (const k of kept) dist = Math.min(dist, Math.abs(sorted[k].time - sorted[i].time));
      const score = sorted[i].score;
      if (dist > bestDist + 1e-9 || (Math.abs(dist - bestDist) <= 1e-9 && score > bestScore)) {
        best = i;
        bestDist = dist;
        bestScore = score;
      }
    }
    if (best < 0) break;
    kept.add(best);
  }

  return [...kept]
    .sort((a, b) => sorted[a].time - sorted[b].time)
    .map((i) => sorted[i]);
}
