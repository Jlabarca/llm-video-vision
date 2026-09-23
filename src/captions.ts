export interface CaptionTrack {
  language: string;
  kind: "manual" | "auto";
}

export interface TranscriptSegment {
  start: number;
  end: number;
  text: string;
}

const STOPWORDS = new Set([
  "what", "when", "where", "which", "who", "whom", "whose", "why", "how",
  "this", "that", "these", "those", "with", "from", "into", "about", "your",
  "have", "does", "did", "was", "were", "are", "the", "and", "for", "video",
  "please", "show", "tell", "look", "there", "their", "them", "then",
]);

/**
 * Manual track in a preferred language, then auto, then any manual, then any auto.
 * `prefer` is tried in order. Prefix match covers `en` vs `en-US` and `pt` vs `pt-BR`.
 */
export function chooseCaptionTrack(
  tracks: CaptionTrack[],
  prefer: string[] = ["en"],
): CaptionTrack | null {
  const prefs = prefer.map((p) => p.toLowerCase()).filter(Boolean);
  const ranked: CaptionTrack[] = [];
  for (const pref of prefs) {
    for (const kind of ["manual", "auto"] as const) {
      const exact = tracks.find((t) => t.kind === kind && t.language.toLowerCase() === pref);
      const prefix = tracks.find(
        (t) => t.kind === kind && t.language.toLowerCase().startsWith(`${pref}-`),
      );
      if (exact) ranked.push(exact);
      if (prefix && prefix !== exact) ranked.push(prefix);
    }
  }
  for (const kind of ["manual", "auto"] as const) {
    const any = tracks.find((t) => t.kind === kind);
    if (any) ranked.push(any);
  }
  return ranked[0] ?? null;
}

/** How much of `duration` the last caption end reaches, 0..1. */
export function coverageRatio(segments: TranscriptSegment[], duration: number): number {
  if (duration <= 0 || segments.length === 0) return 0;
  let maxEnd = 0;
  for (const segment of segments) maxEnd = Math.max(maxEnd, segment.end);
  return Math.min(1, maxEnd / duration);
}

export function questionKeywords(question: string | undefined, limit = 8): string[] {
  if (!question) return [];
  const words = question
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((w) => w.length >= 4 && !STOPWORDS.has(w));
  return [...new Set(words)].slice(0, limit);
}

/** Times where the transcript mentions the question. Used as must-keep frames. */
export function priorityTimes(
  segments: TranscriptSegment[],
  question: string | undefined,
  limit = 3,
): number[] {
  const keys = questionKeywords(question);
  if (keys.length === 0) return [];
  const hits: number[] = [];
  for (const segment of segments) {
    const hay = segment.text.toLowerCase();
    if (keys.some((k) => hay.includes(k))) hits.push(segment.start);
    if (hits.length >= limit) break;
  }
  return hits;
}

export interface CompactOptions {
  times: number[];
  windowSec?: number;
  maxChars?: number;
  question?: string;
  fullPath?: string;
}

/**
 * Lines the model needs: speech near a kept frame, plus question hits.
 * The full transcript stays on disk.
 */
export function compactTranscript(segments: TranscriptSegment[], opts: CompactOptions): string {
  const windowSec = opts.windowSec ?? 8;
  const maxChars = opts.maxChars ?? 2000;
  const keys = questionKeywords(opts.question);
  const picked = segments.filter((segment) => {
    const nearFrame = opts.times.some(
      (t) => segment.end >= t - windowSec && segment.start <= t + windowSec,
    );
    const mentioned = keys.some((k) => segment.text.toLowerCase().includes(k));
    return nearFrame || mentioned;
  });
  const lines = picked.map((segment) => `[${stamp(segment.start)}] ${segment.text.trim()}`);
  let text = lines.join("\n");
  let truncated = false;
  if (text.length > maxChars) {
    text = text.slice(0, maxChars).replace(/\s+\S*$/, "");
    truncated = true;
  }
  if (truncated) {
    const where = opts.fullPath ? ` Full transcript: ${opts.fullPath}` : "";
    text += `\n… excerpt truncated.${where}`;
  }
  return text;
}

function stamp(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  const m = Math.floor(s / 60);
  const sec = s % 60;
  return `${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
}
