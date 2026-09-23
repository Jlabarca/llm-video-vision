import { describe, expect, it } from "vitest";
import { clampBudget, selectFrames } from "../src/select.js";

describe("selectFrames", () => {
  it("covers a one-hour file inside 9 frames instead of the opening minutes", () => {
    const frames = selectFrames({ duration: 3600, budget: 9, scenes: [] });
    expect(frames).toHaveLength(9);
    expect(frames[0].time).toBe(0);
    expect(frames[frames.length - 1].time).toBeGreaterThan(3400);
    const gaps = frames.slice(1).map((frame, i) => frame.time - frames[i].time);
    expect(Math.max(...gaps)).toBeLessThan(600);
  });

  it("keeps a question hit even when the timeline is crowded with cuts", () => {
    const scenes = Array.from({ length: 40 }, (_, i) => ({ time: i * 2, score: 20 }));
    const frames = selectFrames({
      duration: 80,
      budget: 9,
      scenes,
      priorityTimes: [42],
    });
    expect(frames.length).toBeLessThanOrEqual(9);
    expect(frames.some((frame) => frame.reason === "priority" && frame.time === 42)).toBe(true);
    expect(frames[0].time).toBe(0);
    expect(frames[frames.length - 1].time).toBeGreaterThan(70);
  });

  it("ignores scene scores under the shared threshold", () => {
    const frames = selectFrames({
      duration: 10,
      budget: 9,
      floorSeconds: 0,
      scenes: [{ time: 3, score: 2 }, { time: 6, score: 15 }],
    });
    expect(frames.filter((frame) => frame.reason === "scene").map((frame) => frame.time)).toEqual([6]);
  });

  it("clamps a huge budget so a caller cannot dump a hundred images", () => {
    expect(clampBudget(100)).toBe(12);
    expect(selectFrames({ duration: 3600, budget: 100 })).toHaveLength(12);
  });

  it("returns nothing for an empty duration", () => {
    expect(selectFrames({ duration: 0 })).toEqual([]);
  });
});
