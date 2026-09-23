import { mkdtempSync, writeFileSync, mkdirSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { describe, expect, it, vi } from "vitest";
import { watch } from "../src/watch.js";
import type { WatchDeps } from "../src/watch.js";

describe("watch", () => {
  it("returns one sheet, reports a partial analysis, and drops a duplicate thumb", async () => {
    const workDir = mkdtempSync(join(tmpdir(), "lvw-"));
    const grid = vi.fn(async () => undefined);
    const deps: WatchDeps = {
      resolve: async () => ({
        path: "clip.mp4",
        tracks: [{ language: "es", kind: "manual" }],
        cues: [
          { start: 0, end: 2, text: "hola" },
          { start: 40, end: 44, text: "el boton de deploy" },
        ],
      }),
      probe: async () => ({ duration: 60, width: 1280, height: 720, hasAudio: true, codec: "h264" }),
      scenes: async () => ({
        hits: [{ time: 10, score: 20 }, { time: 11, score: 20 }],
        partial: true,
      }),
      thumbs: async (_path, times) => times.map((_, i) => {
        if (i === 1) return new Uint8Array(16).fill(10);
        return new Uint8Array(16).fill(10 + i * 20);
      }),
      frames: async (_path, times, dir) => {
        mkdirSync(dir, { recursive: true });
        return times.map((time, i) => {
          const dest = join(dir, `frame_${String(i + 1).padStart(2, "0")}.jpg`);
          writeFileSync(dest, String(time));
          return dest;
        });
      },
      grid,
    };

    const result = await watch(
      { source: "clip.mp4", question: "deploy button", budget: 9, languages: ["es"], workDir },
      deps,
    );

    expect(result.partial).toBe(true);
    expect(result.manifest).toContain("PARTIAL");
    expect(result.manifest).toContain("manual es");
    expect(result.frames.length).toBeLessThanOrEqual(9);
    expect(result.frames.some((frame) => frame.reason === "priority")).toBe(true);
    expect(grid).toHaveBeenCalledOnce();
    expect(result.gridPath).toBe(join(workDir, "grid.jpg"));
  });
});
