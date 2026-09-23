import { formatHms } from "./time.js";
import type { PickedFrame } from "./select.js";
import type { ProbeResult } from "./parse.js";

export interface ManifestInput {
  source: string;
  resolvedPath: string;
  probe: ProbeResult;
  frames: PickedFrame[];
  droppedAsDuplicate: number;
  analysis: { mode: "keyframes" | "thorough"; partial: boolean; sceneCount: number };
  transcriptSource: string;
  excerpt: string;
  gridPath?: string;
  framePaths: string[];
  paddedCells: number;
}

/** Short enough to sit in a tool result next to one image. */
export function renderManifest(input: ManifestInput): string {
  const lines = [
    `# ${input.probe.width}x${input.probe.height} ${input.probe.codec} ${formatHms(input.probe.duration)}`,
    "",
    `source: ${input.source}`,
    `file: ${input.resolvedPath}`,
    `audio: ${input.probe.hasAudio ? "yes" : "no"}`,
    `analysis: ${input.analysis.mode}, ${input.analysis.sceneCount} cuts${input.analysis.partial ? ", PARTIAL (timed out — scene list is incomplete)" : ""}`,
    `frames: ${input.frames.length} kept, ${input.droppedAsDuplicate} near-duplicates dropped`,
    `transcript: ${input.transcriptSource}`,
  ];
  if (input.gridPath) lines.push(`grid: ${input.gridPath}`);
  if (input.paddedCells > 0) {
    lines.push(`grid padding: last frame repeated ${input.paddedCells} time(s) to fill the sheet`);
  }
  lines.push("", "## Frames", "");
  input.frames.forEach((frame, i) => {
    const path = input.framePaths[i] ? ` ${input.framePaths[i]}` : "";
    lines.push(`- ${formatHms(frame.time)} ${frame.reason} score=${frame.score}${path}`);
  });
  if (input.excerpt) {
    lines.push("", "## Transcript excerpt", "", input.excerpt);
  } else {
    lines.push("", "No transcript in context. Captions were missing, or local Whisper is not configured (`LVW_WHISPER_MODEL`).");
  }
  lines.push(
    "",
    "Read the grid left to right, top to bottom. It matches the frame list.",
    "Ask for `detail` on a timestamp only when this sheet does not answer the question.",
  );
  return lines.join("\n");
}
