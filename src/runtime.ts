import { execFile } from "child_process";
import { createHash } from "crypto";
import { existsSync, mkdirSync, copyFileSync, readFileSync, readdirSync, statSync } from "fs";
import { homedir } from "os";
import { join, resolve } from "path";
import { chooseCaptionTrack } from "./captions.js";
import type { CaptionTrack, TranscriptSegment } from "./captions.js";
import {
  firstExisting,
  FONT_CANDIDATES,
  frameArgs,
  frameArgsNoText,
  probeArgs,
  sceneArgs,
  thumbArgs,
  tileArgs,
} from "./ffmpeg.js";
import { parseCues, parseProbe, parseScdet } from "./parse.js";
import type { ProbeResult } from "./parse.js";
import type { SceneHit } from "./select.js";
import type { WatchDeps } from "./watch.js";

interface RunResult {
  stdout: Buffer;
  stderr: string;
  code: number;
  timedOut: boolean;
}

export function runFile(cmd: string, args: string[], timeoutMs: number): Promise<RunResult> {
  return new Promise((resolvePromise, reject) => {
    execFile(
      cmd,
      args,
      { timeout: timeoutMs, maxBuffer: 32 * 1024 * 1024, windowsHide: true, encoding: "buffer" },
      (err, stdout, stderr) => {
        const error = err as NodeJS.ErrnoException & { killed?: boolean };
        if (error?.code === "ENOENT") {
          reject(new Error(`'${cmd}' was not found on PATH.`));
          return;
        }
        const out = Buffer.isBuffer(stdout) ? stdout : Buffer.from(stdout ?? "");
        const errText = Buffer.isBuffer(stderr) ? stderr.toString("utf8") : String(stderr ?? "");
        const timedOut = Boolean(error && (error.killed || error.code === "ETIMEDOUT"));
        const code = error ? (typeof error.code === "number" ? error.code : 1) : 0;
        resolvePromise({ stdout: out, stderr: errText, code, timedOut });
      },
    );
  });
}

export function isHttpUrl(input: string): boolean {
  try {
    const url = new URL(input);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

export function sessionDir(source: string, root = join(homedir(), ".llm-video-vision", "sessions")): string {
  const id = createHash("sha256").update(source).digest("hex").slice(0, 16);
  return join(root, id);
}

export function tracksFromInfo(data: {
  subtitles?: Record<string, unknown>;
  automatic_captions?: Record<string, unknown>;
}): CaptionTrack[] {
  const tracks: CaptionTrack[] = [];
  for (const language of Object.keys(data.subtitles ?? {})) tracks.push({ language, kind: "manual" });
  for (const language of Object.keys(data.automatic_captions ?? {})) tracks.push({ language, kind: "auto" });
  return tracks;
}

export async function probeFile(path: string): Promise<ProbeResult> {
  const result = await runFile("ffprobe", probeArgs(path), 30_000);
  if (result.code !== 0) {
    throw new Error(`ffprobe failed: ${result.stderr.slice(-400)}`);
  }
  return parseProbe(result.stdout.toString("utf8"));
}

export async function analyzeScenes(
  path: string,
  thorough: boolean,
): Promise<{ hits: SceneHit[]; partial: boolean }> {
  const result = await runFile("ffmpeg", sceneArgs(path, thorough), thorough ? 180_000 : 90_000);
  const useful = result.stderr.includes("lavfi.scd");
  if (result.code !== 0 && !result.timedOut && !useful) {
    throw new Error(`ffmpeg scene pass failed: ${result.stderr.slice(-500)}`);
  }
  return { hits: parseScdet(result.stderr, 10), partial: result.timedOut };
}

export async function extractThumbs(path: string, times: number[]): Promise<Uint8Array[]> {
  const out: Uint8Array[] = [];
  for (const time of times) {
    const result = await runFile("ffmpeg", thumbArgs(path, time), 30_000);
    out.push(result.code === 0 ? new Uint8Array(result.stdout) : new Uint8Array());
  }
  return out;
}

export async function extractFrames(
  path: string,
  times: number[],
  dir: string,
  width: number,
): Promise<string[]> {
  mkdirSync(dir, { recursive: true });
  const font = firstExisting(FONT_CANDIDATES, existsSync);
  const written: string[] = [];
  for (let i = 0; i < times.length; i++) {
    const dest = join(dir, `frame_${String(i + 1).padStart(2, "0")}.jpg`);
    const burned = await runFile("ffmpeg", frameArgs(path, times[i], dest, width, font), 60_000);
    if (burned.code !== 0 || !existsSync(dest)) {
      const plain = await runFile("ffmpeg", frameArgsNoText(path, times[i], dest, width), 60_000);
      if (plain.code !== 0 || !existsSync(dest)) {
        throw new Error(`ffmpeg could not extract ${times[i]}: ${plain.stderr.slice(-400)}`);
      }
    }
    written.push(dest);
  }
  return written;
}

export async function writeGrid(framePaths: string[], output: string): Promise<void> {
  const dir = join(output, "..", "sheet");
  mkdirSync(dir, { recursive: true });
  framePaths.forEach((file, i) => {
    copyFileSync(file, join(dir, `frame_${String(i + 1).padStart(2, "0")}.jpg`));
  });
  const result = await runFile(
    "ffmpeg",
    tileArgs(join(dir, "frame_%02d.jpg"), framePaths.length, output),
    60_000,
  );
  if (result.code !== 0 || !existsSync(output)) {
    throw new Error(`ffmpeg grid failed: ${result.stderr.slice(-400)}`);
  }
}

export function createRuntime(languages: string[] = ["en"]): WatchDeps {
  return {
    probe: probeFile,
    scenes: analyzeScenes,
    thumbs: extractThumbs,
    frames: extractFrames,
    grid: writeGrid,
    resolve: (source) => resolveSource(source, languages),
  };
}

export async function resolveSource(
  source: string,
  languages: string[],
): Promise<{ path: string; tracks: CaptionTrack[]; cues?: TranscriptSegment[] }> {
  if (!isHttpUrl(source)) {
    const path = resolve(source);
    if (!existsSync(path) || !statSync(path).isFile()) {
      throw new Error(`File not found: ${path}`);
    }
    return { path, tracks: [] };
  }

  const dir = sessionDir(`${source}:download`);
  mkdirSync(dir, { recursive: true });
  const info = await runFile(
    "yt-dlp",
    ["--skip-download", "--no-playlist", "--dump-single-json", source],
    60_000,
  );
  if (info.code !== 0) throw new Error(`yt-dlp failed: ${info.stderr.slice(-400)}`);
  const data = JSON.parse(info.stdout.toString("utf8")) as {
    subtitles?: Record<string, unknown>;
    automatic_captions?: Record<string, unknown>;
  };
  const tracks = tracksFromInfo(data);
  const chosen = chooseCaptionTrack(tracks, languages);
  const cues = chosen ? await fetchCues(source, chosen, dir) : undefined;
  const path = await downloadVideo(source, dir);
  return { path, tracks, cues };
}

async function fetchCues(
  url: string,
  track: CaptionTrack,
  dir: string,
): Promise<TranscriptSegment[] | undefined> {
  const args = [
    "--skip-download", "--no-playlist",
    "--sub-langs", track.language,
    "--sub-format", "srt/vtt/best",
    "-o", join(dir, "subs.%(ext)s"),
    track.kind === "manual" ? "--write-subs" : "--write-auto-subs",
    url,
  ];
  await runFile("yt-dlp", args, 60_000);
  const file = readdirSync(dir).find((name) => name.endsWith(".srt") || name.endsWith(".vtt"));
  if (!file) return undefined;
  return parseCues(readFileSync(join(dir, file), "utf8"));
}

async function downloadVideo(url: string, dir: string): Promise<string> {
  const cached = readdirSync(dir).find((name) => name.startsWith("video."));
  if (cached) return join(dir, cached);
  const result = await runFile(
    "yt-dlp",
    [
      "--no-playlist", "--no-warnings", "--restrict-filenames",
      "--merge-output-format", "mp4",
      "-f", "bv*[height<=720]+ba/b[height<=720]/b",
      "-o", join(dir, "video.%(ext)s"),
      "--print", "after_move:filepath",
      url,
    ],
    20 * 60 * 1000,
  );
  if (result.code !== 0) throw new Error(`yt-dlp download failed: ${result.stderr.slice(-400)}`);
  const printed = result.stdout.toString("utf8").trim().split(/\r?\n/).filter(Boolean).pop();
  if (printed && existsSync(printed)) return printed;
  const found = readdirSync(dir).find((name) => name.startsWith("video."));
  if (!found) throw new Error("yt-dlp did not produce a video file");
  return join(dir, found);
}
