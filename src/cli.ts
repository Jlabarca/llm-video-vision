#!/usr/bin/env node
import { createRuntime, sessionDir } from "./runtime.js";
import { watch } from "./watch.js";

interface Flags {
  source?: string;
  question?: string;
  budget?: number;
  languages: string[];
  thorough: boolean;
  start?: number;
  end?: number;
  json: boolean;
}

function parseArgv(argv: string[]): Flags {
  const flags: Flags = { languages: ["en"], thorough: false, json: false };
  const rest: string[] = [];
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = () => argv[++i];
    if (arg === "--question") flags.question = next();
    else if (arg === "--budget") flags.budget = Number(next());
    else if (arg === "--lang") flags.languages = next().split(",").map((s) => s.trim()).filter(Boolean);
    else if (arg === "--thorough") flags.thorough = true;
    else if (arg === "--start") flags.start = Number(next());
    else if (arg === "--end") flags.end = Number(next());
    else if (arg === "--json") flags.json = true;
    else if (arg === "--help" || arg === "-h") {
      flags.source = "--help";
    } else if (!arg.startsWith("-")) rest.push(arg);
    else throw new Error(`Unknown flag ${arg}`);
  }
  if (!flags.source) flags.source = rest[0];
  return flags;
}

function help(): string {
  return `lvw <file-or-url> [--question "..."] [--budget 9] [--lang es,en] [--start SEC --end SEC] [--thorough] [--json]

Watch a video inside a fixed image budget (default 9, cap 12).
Writes manifest.md, frames/, and one grid.jpg under ~/.llm-video-vision/sessions/.
Prints the manifest. Needs ffmpeg and ffprobe. URLs also need yt-dlp.`;
}

async function main() {
  const flags = parseArgv(process.argv.slice(2));
  if (!flags.source || flags.source === "--help") {
    console.log(help());
    process.exit(flags.source === "--help" ? 0 : 1);
  }
  const window = flags.start != null || flags.end != null
    ? { start: flags.start ?? 0, end: flags.end ?? (flags.start ?? 0) + 5 }
    : undefined;
  const result = await watch(
    {
      source: flags.source,
      question: flags.question,
      budget: window ? (flags.budget ?? 6) : flags.budget,
      languages: flags.languages,
      thorough: flags.thorough,
      workDir: sessionDir(window ? `${flags.source}@${window.start}-${window.end}` : flags.source),
      window,
    },
    createRuntime(flags.languages),
  );
  if (flags.json) {
    console.log(JSON.stringify({
      evidenceDir: result.evidenceDir,
      gridPath: result.gridPath,
      frames: result.frames,
      partial: result.partial,
      manifest: result.manifest,
    }, null, 2));
  } else {
    console.log(result.manifest);
    console.log(`\nevidence: ${result.evidenceDir}`);
  }
}

main().catch((err: unknown) => {
  console.error(err instanceof Error ? err.message : String(err));
  process.exit(1);
});
