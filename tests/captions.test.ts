import { describe, expect, it } from "vitest";
import {
  chooseCaptionTrack,
  compactTranscript,
  coverageRatio,
  priorityTimes,
} from "../src/captions.js";
import { dropNearDuplicates, meanAbsDiff } from "../src/pixels.js";

describe("captions", () => {
  it("prefers a manual track in the requested language over English auto-captions", () => {
    const chosen = chooseCaptionTrack(
      [
        { language: "en", kind: "auto" },
        { language: "es", kind: "manual" },
        { language: "en", kind: "manual" },
      ],
      ["es", "en"],
    );
    expect(chosen).toEqual({ language: "es", kind: "manual" });
  });

  it("falls through to any manual track when nothing matches the preference", () => {
    expect(chooseCaptionTrack([{ language: "pt-BR", kind: "manual" }], ["ja"])).toEqual({
      language: "pt-BR",
      kind: "manual",
    });
  });

  it("measures how much of the file the cues cover", () => {
    expect(coverageRatio([{ start: 0, end: 12, text: "hi" }], 60)).toBeCloseTo(0.2);
  });

  it("keeps the excerpt short and points at the full file", () => {
    const segments = Array.from({ length: 40 }, (_, i) => ({
      start: i * 10,
      end: i * 10 + 4,
      text: "word ".repeat(30),
    }));
    const text = compactTranscript(segments, {
      times: [0],
      windowSec: 5,
      maxChars: 120,
      fullPath: "C:/sessions/transcript.txt",
    });
    expect(text.length).toBeLessThan(220);
    expect(text).toContain("transcript.txt");
    expect(text).toContain("truncated");
  });

  it("turns question words into frame times", () => {
    expect(
      priorityTimes(
        [
          { start: 4, end: 6, text: "the deploy button is in the corner" },
          { start: 20, end: 22, text: "unrelated" },
        ],
        "where is the deploy button",
      ),
    ).toEqual([4]);
  });
});

describe("pixels", () => {
  it("drops a near-duplicate and keeps a real change", () => {
    const a = new Uint8Array([0, 0, 0, 10]);
    const b = new Uint8Array([1, 1, 1, 11]);
    const c = new Uint8Array([200, 10, 10, 10]);
    expect(meanAbsDiff(a, b)).toBeLessThan(12);
    const kept = dropNearDuplicates(
      [{ id: "a", pixels: a }, { id: "b", pixels: b }, { id: "c", pixels: c }],
      12,
    );
    expect(kept.map((frame) => frame.id)).toEqual(["a", "c"]);
  });
});
