import type { SceneHit } from "./select.js";
import type { TranscriptSegment } from "./captions.js";

export interface ProbeResult {
  duration: number;
  width: number;
  height: number;
  hasAudio: boolean;
  codec: string;
}

/** ffprobe JSON (`-show_format -show_streams`) -> the fields watch cares about. */
export function parseProbe(json: string): ProbeResult {
  const probe = JSON.parse(json) as {
    streams?: Array<Record<string, unknown>>;
    format?: Record<string, unknown>;
  };
  const streams = probe.streams ?? [];
  const video = streams.find((s) => s.codec_type === "video");
  const audio = streams.find((s) => s.codec_type === "audio");
  const duration = parseFloat(String(probe.format?.duration ?? video?.duration ?? "0")) || 0;
  return {
    duration,
    width: Number(video?.width ?? 0),
    height: Number(video?.height ?? 0),
    hasAudio: Boolean(audio),
    codec: String(video?.codec_name ?? "unknown"),
  };
}

/**
 * Scene cuts from ffmpeg `metadata=mode=print` on stderr or a metadata file.
 * Accepts either `lavfi.scd.time=` or the preceding `pts_time:`.
 */
/**
 * A cut is a `lavfi.scd.time` line, not every frame that carries a score.
 * Score and time are often on sibling lines under the same `pts_time`.
 */
export function parseScdet(text: string, minScore = 0): SceneHit[] {
  const results: SceneHit[] = [];
  let score: number | null = null;
  for (const line of text.split(/\r?\n/)) {
    if (/pts_time:/.test(line)) score = null;
    const scoreMatch = line.match(/lavfi\.scd\.score=([0-9.]+)/);
    if (scoreMatch) score = parseFloat(scoreMatch[1]);
    const timeMatch = line.match(/lavfi\.scd\.time=([0-9.]+)/);
    if (!timeMatch || score == null || score < minScore) continue;
    results.push({ time: parseFloat(timeMatch[1]), score });
  }
  return results;
}

/** SRT or WebVTT cues. Hours are optional. Milliseconds are kept on the numbers. */
export function parseCues(raw: string): TranscriptSegment[] {
  const blocks = raw.replace(/\r/g, "").replace(/^WEBVTT[^\n]*\n+/, "").split(/\n{2,}/);
  const segments: TranscriptSegment[] = [];
  for (const block of blocks) {
    const lines = block.split("\n").map((l) => l.trim()).filter(Boolean);
    const timingIndex = lines.findIndex((line) => line.includes("-->"));
    if (timingIndex === -1) continue;
    const [startRaw, endRaw] = lines[timingIndex].split("-->").map((p) => p.trim());
    if (!startRaw || !endRaw) continue;
    const text = lines
      .slice(timingIndex + 1)
      .join(" ")
      .replace(/<[^>]+>/g, "")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, "\"")
      .replace(/&#39;/g, "'")
      .replace(/\s+/g, " ")
      .trim();
    if (!text) continue;
    segments.push({
      start: parseCueTime(startRaw),
      end: parseCueTime(endRaw),
      text,
    });
  }
  return segments;
}

export function parseCueTime(raw: string): number {
  const match = raw.trim().match(/(?:(\d+):)?(\d{1,2}):(\d{2})[,.](\d{3})/);
  if (!match) return 0;
  const hours = Number(match[1] ?? 0);
  const minutes = Number(match[2]);
  const seconds = Number(match[3]);
  const millis = Number(match[4]);
  return hours * 3600 + minutes * 60 + seconds + millis / 1000;
}
