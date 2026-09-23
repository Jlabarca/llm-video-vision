import { mkdirSync, copyFileSync, writeFileSync, rmSync } from "fs";
import { join } from "path";
import { chooseCaptionTrack, compactTranscript, coverageRatio, priorityTimes } from "./captions.js";
import type { CaptionTrack, TranscriptSegment } from "./captions.js";
import { renderManifest } from "./evidence.js";
import { gridShape } from "./ffmpeg.js";
import { dropNearDuplicates } from "./pixels.js";
import type { ProbeResult } from "./parse.js";
import { selectFrames } from "./select.js";
import type { PickedFrame, SceneHit } from "./select.js";

export interface WatchRequest {
  source: string;
  question?: string;
  budget?: number;
  languages?: string[];
  thorough?: boolean;
  width?: number;
  workDir: string;
  /** When set, only this window is sampled. Used by `detail`. */
  window?: { start: number; end: number };
}

export interface WatchResult {
  manifest: string;
  gridPath?: string;
  framePaths: string[];
  frames: PickedFrame[];
  evidenceDir: string;
  partial: boolean;
}

export interface WatchDeps {
  probe(path: string): Promise<ProbeResult>;
  scenes(path: string, thorough: boolean): Promise<{ hits: SceneHit[]; partial: boolean }>;
  thumbs(path: string, times: number[]): Promise<Uint8Array[]>;
  frames(path: string, times: number[], dir: string, width: number): Promise<string[]>;
  grid(framePaths: string[], output: string): Promise<void>;
  resolve(source: string): Promise<{ path: string; tracks: CaptionTrack[]; cues?: TranscriptSegment[] }>;
}

interface WithPixels extends PickedFrame {
  pixels?: Uint8Array;
}

/**
 * One perception pass. The image count never exceeds the budget, the sheet
 * is a single file, and a timed-out analysis is labeled partial.
 */
export async function watch(req: WatchRequest, deps: WatchDeps): Promise<WatchResult> {
  const resolved = await deps.resolve(req.source);
  const probe = await deps.probe(resolved.path);
  const width = req.width ?? (req.window ? 640 : 320);

  let duration = probe.duration;
  let offset = 0;
  if (req.window) {
    offset = Math.max(0, req.window.start);
    duration = Math.max(0, Math.min(probe.duration, req.window.end) - offset);
  }

  const analysis = await deps.scenes(resolved.path, Boolean(req.thorough));
  let hits = analysis.hits;
  if (req.window) {
    hits = hits
      .filter((h) => h.time >= offset && h.time <= offset + duration)
      .map((h) => ({ ...h, time: h.time - offset }));
  }

  const segments = resolved.cues ?? [];
  const usableCaptions =
    segments.length > 0 && (probe.duration < 30 || coverageRatio(segments, probe.duration) >= 0.5);
  const transcriptSource = usableCaptions
    ? describeTrack(resolved.tracks, req.languages)
    : "none";

  const windowSegments = req.window
    ? segments
        .filter((s) => s.end >= offset && s.start <= offset + duration)
        .map((s) => ({ ...s, start: Math.max(0, s.start - offset), end: s.end - offset }))
    : segments;

  const picked = selectFrames({
    duration,
    scenes: hits,
    budget: req.budget,
    priorityTimes: priorityTimes(windowSegments, req.question),
    floorSeconds: req.window ? Math.max(1, duration / 6) : 30,
  });

  mkdirSync(req.workDir, { recursive: true });
  rmSync(join(req.workDir, "frames"), { recursive: true, force: true });
  rmSync(join(req.workDir, "grid.jpg"), { force: true });
  const thumbs = await deps.thumbs(
    resolved.path,
    picked.map((f) => f.time + offset),
  );
  const withPixels: WithPixels[] = picked.map((frame, i) => ({ ...frame, pixels: thumbs[i] }));
  const unique = dropNearDuplicates(withPixels);
  const dropped = withPixels.length - unique.length;
  const kept = unique.map(({ pixels: _pixels, ...frame }) => frame);

  const frameDir = join(req.workDir, "frames");
  mkdirSync(frameDir, { recursive: true });
  const extracted = await deps.frames(
    resolved.path,
    kept.map((f) => f.time + offset),
    frameDir,
    width,
  );

  let gridPath: string | undefined;
  let paddedCells = 0;
  if (extracted.length > 0) {
    const { cols, rows } = gridShape(extracted.length);
    const slots = cols * rows;
    paddedCells = slots - extracted.length;
    const tiled = [...extracted];
    for (let i = extracted.length; i < slots; i++) {
      const pad = join(frameDir, `pad_${String(i).padStart(2, "0")}.jpg`);
      copyFileSync(extracted[extracted.length - 1], pad);
      tiled.push(pad);
    }
    gridPath = join(req.workDir, "grid.jpg");
    await deps.grid(tiled, gridPath);
  }

  const fullTranscriptPath = join(req.workDir, "transcript.txt");
  if (segments.length > 0) {
    const body = segments
      .map((s) => `[${formatStamp(s.start)}] ${s.text}`)
      .join("\n");
    writeFileSync(fullTranscriptPath, body, "utf8");
  }

  const excerpt = usableCaptions
    ? compactTranscript(windowSegments, {
        times: kept.map((f) => f.time),
        question: req.question,
        fullPath: fullTranscriptPath,
      })
    : "";

  const manifest = renderManifest({
    source: req.source,
    resolvedPath: resolved.path,
    probe: req.window
      ? { ...probe, duration }
      : probe,
    frames: kept,
    droppedAsDuplicate: dropped,
    analysis: {
      mode: req.thorough ? "thorough" : "keyframes",
      partial: analysis.partial,
      sceneCount: hits.length,
    },
    transcriptSource,
    excerpt,
    gridPath,
    framePaths: extracted,
    paddedCells,
  });
  writeFileSync(join(req.workDir, "manifest.md"), manifest, "utf8");

  return {
    manifest,
    gridPath,
    framePaths: extracted,
    frames: kept,
    evidenceDir: req.workDir,
    partial: analysis.partial,
  };
}

function describeTrack(tracks: CaptionTrack[], languages?: string[]): string {
  const chosen = chooseCaptionTrack(tracks, languages ?? ["en"]);
  if (!chosen) return "captions";
  return `${chosen.kind} ${chosen.language}`;
}

function formatStamp(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (h > 0) {
    return [h, m, sec].map((n) => String(n).padStart(2, "0")).join(":");
  }
  return `${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
}
