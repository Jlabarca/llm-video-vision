import { formatHms } from "./time.js";

export const FONT_CANDIDATES = [
  "C:/Windows/Fonts/arial.ttf",
  "C:/Windows/Fonts/segoeui.ttf",
  "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
  "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
  "/System/Library/Fonts/Supplemental/Arial.ttf",
  "/Library/Fonts/Arial.ttf",
];

export function firstExisting(paths: string[], exists: (p: string) => boolean): string | null {
  return paths.find((p) => exists(p)) ?? null;
}

/** lavfi treats `:` as a separator and `\` as an escape. Drive letters need both. */
export function escapeLavfiPath(p: string): string {
  return p.replace(/\\/g, "/").replace(/^([A-Za-z]):/, "$1\\\\:");
}

export function drawtextFilter(timestamp: string, fontFile: string | null): string {
  const text = timestamp.replace(/:/g, "\\:");
  const font = fontFile ? `:fontfile=${escapeLavfiPath(fontFile)}` : "";
  return `drawtext=text='${text}'${font}:fontsize=16:fontcolor=white:box=1:boxcolor=black@0.55:x=6:y=h-th-6`;
}

/**
 * Scene pass. The default skips to keyframes so a 4K file does not decode
 * every frame. `--thorough` samples 2 fps instead, still at 320px.
 * Scores land on stderr via `metadata=mode=print` (no path, so no Windows escape).
 */
export function sceneArgs(input: string, thorough: boolean): string[] {
  const vf = thorough
    ? "fps=2,scale=320:-2,scdet=threshold=10,metadata=mode=print"
    : "scale=320:-2,scdet=threshold=10,metadata=mode=print";
  const args = ["-hide_banner", "-nostats"];
  if (!thorough) args.push("-skip_frame", "nokey");
  args.push("-i", input, "-vf", vf, "-an", "-f", "null", "-");
  return args;
}

export function probeArgs(input: string): string[] {
  return ["-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", input];
}

/** One frame at an absolute timestamp, scaled, with the clock burned in. */
export function frameArgs(
  input: string,
  time: number,
  output: string,
  width: number,
  fontFile: string | null,
): string[] {
  const vf = `scale=${width}:-2,${drawtextFilter(formatHms(time), fontFile)}`;
  return [
    "-hide_banner", "-nostats",
    "-ss", time.toFixed(3),
    "-i", input,
    "-frames:v", "1",
    "-vf", vf,
    "-q:v", "5",
    "-y", output,
  ];
}

export function frameArgsNoText(input: string, time: number, output: string, width: number): string[] {
  return [
    "-hide_banner", "-nostats",
    "-ss", time.toFixed(3),
    "-i", input,
    "-frames:v", "1",
    "-vf", `scale=${width}:-2`,
    "-q:v", "5",
    "-y", output,
  ];
}

/** 32×32 RGB thumb for pixel dedup. 3072 bytes on stdout. */
export function thumbArgs(input: string, time: number): string[] {
  return [
    "-hide_banner", "-nostats",
    "-ss", time.toFixed(3),
    "-i", input,
    "-frames:v", "1",
    "-vf", "scale=32:32",
    "-f", "rawvideo",
    "-pix_fmt", "rgb24",
    "pipe:1",
  ];
}

export function gridShape(count: number): { cols: number; rows: number } {
  if (count <= 1) return { cols: 1, rows: 1 };
  if (count <= 3) return { cols: count, rows: 1 };
  if (count <= 4) return { cols: 2, rows: 2 };
  if (count <= 6) return { cols: 3, rows: 2 };
  if (count <= 9) return { cols: 3, rows: 3 };
  return { cols: 4, rows: 3 };
}

/**
 * Contact sheet from a sequential `frame_%02d.jpg` pattern.
 * `count` is the number of real frames. The caller repeats the last file
 * until `cols * rows` so tile always closes the rectangle.
 */
export function tileArgs(pattern: string, count: number, output: string): string[] {
  const { cols, rows } = gridShape(count);
  return [
    "-hide_banner", "-nostats", "-y",
    "-framerate", "1",
    "-start_number", "1",
    "-i", pattern,
    "-frames:v", String(cols * rows),
    "-vf", `tile=${cols}x${rows}:padding=4:margin=4:color=0x111111`,
    "-q:v", "5",
    output,
  ];
}
