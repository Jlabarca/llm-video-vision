# Upstream study — claude-video-vision

> Studied 2026-09-23 from a shallow clone of `main` at v1.3.2
> (`5c8bc7b`, plus a README-only commit on 2026-08-07).
> Source: <https://github.com/jordanrendric/claude-video-vision>
> This repo (`jlabarca/llm-video-vision`) is an original implementation of the
> decisions at the bottom. It is not a fork. Upstream is MIT; we credit the idea
> and do not copy its source.

## What upstream is

A Claude Code plugin and stdio MCP server. It is a perception layer: ffmpeg
pulls frames, an audio backend writes a transcript, and the host model does
the interpretation. Six tools: `video_info`, `video_analyze`, `video_watch`,
`video_detail`, `video_configure`, `video_setup`.

About 1.3k stars and 156 forks at study time. Last code change 2026-05-18.
Seven functional issues were still open, including one filed 2026-09-07.
README status still says "v1.0.0, tested on macOS Apple Silicon" while
`plugin.json` says 1.2.0 and the npm package says 1.3.2. Install docs assume
`brew`.

Default behavior:

- Uniform fps, 512px JPEG, hard cap of 100 frames, returned as inline base64.
- Audio via Gemini, whisper.cpp, openai-whisper, or the OpenAI Whisper API.
- YouTube is the only URL. English manual captions win, then English
  auto-captions, then the configured backend.
- A skill requires six steps for any video longer than 30 seconds: info,
  analyze, plan segments, watch, drill in, answer.
- The session cache that would make a follow-up cheap is off
  (`enable_index: false`).

## Where the category moved

Each neighbor took one slice. None ships scene-aware frames, a hard image
budget, and a host-agnostic install together.

| Project | What it added |
|---|---|
| [bengemine/agent-video-vision](https://github.com/bengemine/agent-video-vision) | Claude Code and Codex, local transcription only |
| [OAMaestro/video-vision-mcp](https://github.com/OAMaestro/video-vision-mcp) | Any MCP host, scene mode, burned-in timestamps, contact sheets |
| [HUANGCHIHHUNGLeo/claude-real-video](https://github.com/HUANGCHIHHUNGLeo/claude-real-video) | Scene-change frames, pixel-diff dedup, 3×3 grids, a folder any chat can read |
| [bradautomates/claude-video](https://github.com/bradautomates/claude-video) | `/watch` plus a skill install that reaches many agent hosts |
| [simonw/llm-video-frames](https://github.com/simonw/llm-video-frames) | One `llm` fragment, timestamp drawn on the frame |

## Defects in the current source

1. **Long videos are cut off at the start.** `extractFrames` applies
   `-frames:v` (default 100) after a low fps. A one-hour file at the auto
   rate of 0.2 fps wants ~720 frames and keeps the first 100, about eight
   minutes. The README line "low fps, full duration" does not span the file.
   Sample across the whole timeline, then cap.

2. **`video_analyze` reports success when ffmpeg is killed.** The pass has a
   600s timeout. The `catch` treats `SIGTERM` like a filter that exited
   non-zero and still wrote useful logs. The caller gets empty `scenes` and
   `silence_intervals`. Issue #58: a 4K AV1 source ran at 0.085× realtime, so
   600s of wall clock decoded 51 seconds, and the metadata file stayed empty
   because `metadata=mode=print:file=` never flushed. Issue #47 (scenes ending
   near 01:09 on a long film) is the same wall. Downscale or skip frames
   before the expensive filters, and return `partial: true` with the timestamp
   actually reached.

3. **Scene threshold disagrees with itself.** The filter is built as
   `scdet=threshold=10`. `parseScdetFromMetaFile` keeps every score ≥ 2.
   Motion inside a shot becomes a fake cut (issue #45). One threshold, both
   places, caller-visible.

4. **Analysis runs at native resolution.** `siti`, `blurdetect`, and
   `signalstats` decode every 4K frame. A proxy (or keyframe-only) pass is
   the performance fix.

5. **Segments share one output directory.** `extractFramesBySegments` writes
   every segment to `frame_%04d.jpg` in the same folder. The next segment
   overwrites `frame_0001`, and a later `readdir` mixes leftovers. That
   matches issue #46.

6. **`-ss` before `-i` and `-to` after `-i`.** Models also pass `end_time` as
   a duration (issue #35). The argv has to make "absolute end" and "duration"
   unambiguous.

7. **`generateTimestampsForSegment` rounds every sample to a whole second**
   (`formatHMS(Math.round(t))`). Two frames per second collapse onto one stamp.

8. **Captions are English-only and second-resolution.**
   `chooseCaptionTrack` hardcodes `en`, `en-orig`, `en-US`, `en-GB`. A
   Spanish or Portuguese video with good manual captions is treated as
   "no captions" and sent to Whisper.

9. **`whisper_at` does not tag non-speech on the local path** (issue #41).
   Gemini is the only backend that returns `audio_tags`. Chunk overlap is
   stored and unused (`audio_chunk_overlap_seconds`, comment says the dedup
   post-processor is TBD).

10. **Windows is unfinished.** Model download shells out to `curl`. The VAD
    model is not checksummed. The binary is assumed to be `whisper-cli` on
    `PATH`. `npm run build` is `tsc && chmod +x`.

11. **Version drift.** README, plugin manifest, and npm disagree.

## Product gaps

**The model is the scheduler.** The skill orders a six-step dance. When
analyze returns an empty success, the model extracts the wrong frames and
answers anyway. One `watch` call should run the cheap perception pass and
return a small evidence pack. Drill-down stays a second call.

**Frames are uniform, not scene-aware.** Fixed fps over-samples a slide and
misses a fast cut. Scene score, a density floor, and a pixel diff (downscaled
RGB, not a hash) are the selection that neighboring tools already showed works.

**Images are unbounded.** Up to 100 inline base64 frames. Some hosts cannot
see inline MCP images at all and need file paths. A 3×3 contact sheet with the
timestamp burned into each cell is one image. A text label before the image
falls off as soon as a client reorders content.

**No evidence folder.** A directory of `manifest.md`, transcript, frames, and
one grid is what you drop into a chat that has no MCP, and it is the cache.

**Claude-shaped.** Describer models are `opus | sonnet | haiku`. Descriptions
mode still attaches the images and hopes a Claude subagent reads them. The
name `llm-video-vision` is the positioning: any MCP host, one skill, a CLI.

**YouTube only.** yt-dlp already speaks Vimeo, X, TikTok, and a raw media URL.
Playlists stay off unless asked.

**No published eval.** A dozen clips (slides, fast cuts, a screencast, two
speakers, a one-second event, a 4K long video) scored on "did the event get a
frame", "how many images", and "did the transcript cite the right time" is
the artifact that makes a successor spread.

## Decisions this repo ships

Locked 2026-09-23. The constraint is fewer tokens with the timeline still covered.

| Choice | Why |
|---|---|
| One `watch` call, default budget **9 frames**, hard cap **12** | One 3×3 sheet instead of a stack of stills. The cap is the product, not a suggestion the model can ignore. |
| Keyframe scene detect at 320px, plus a 30s floor, then farthest-point thinning | Spans the whole file. Skips the full-frame 4K decode that makes upstream time out. `--thorough` exists for fast cuts inside a GOP. |
| Pixel dedup on 32×32 thumbs before the full extract | Near-duplicate slides never become a second image. |
| One contact sheet, timestamps burned in, paths always returned | Hosts that cannot see MCP images still have files. Hosts that can see images pay for one picture. |
| Captions before Whisper, language preference not hardcoded to English | A manual track in the requested language wins. Local Whisper runs only when `LVW_WHISPER_MODEL` is set. |
| Transcript excerpt in the tool result, full text on disk | Speech stays available without pasting an hour of captions into context. |
| `detail` is a short window with its own small budget | Drill-down is explicit. The first answer does not pre-load it. |
| Analysis timeout is reported as `partial: true` | An empty scene list is never a silent success. |
| Original TypeScript, stdio MCP + `lvw` CLI | Same distribution shape as the category, none of the Claude-only plugin surface. |

Deferred on purpose: speaker diarization, a local vision describer, streamable
HTTP, auto-download of Whisper weights, and the public eval set. Those add
tokens, setup, or scope before the budgeted watch path is the default.
