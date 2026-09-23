# llm-video-vision

Watch a video with any LLM, and spend a fixed number of images doing it.

`lvw` and the `watch` MCP tool turn a local file or a URL into **one contact sheet** plus a short transcript excerpt. The sheet covers the whole timeline: scene cuts when they are cheap to see, a frame at least every 30 seconds, then farthest-point thinning down to a budget of 9 (never more than 12). Near-duplicate slides are dropped before they become a second image.

This is a perception layer. The model still answers. The tool decides which pictures are worth sending.

```bash
node dist/cli.js path/to/video.mp4 --question "what changed on screen"
node dist/cli.js "https://www.youtube.com/watch?v=..." --lang es,en
```

Evidence lands in `~/.llm-video-vision/sessions/<id>/` as `manifest.md`, `frames/`, `grid.jpg`, and `transcript.txt` when captions exist.

## Why the budget is the product

Uniform frame dumps miss the point twice. A one-hour lecture sampled at a low fps and then capped at the first N frames never shows the ending. A hundred inline images blow the context window and still repeat the same slide. The selection here is:

1. Keyframe scene detection at 320px (`scdet` threshold 10). A 4K file is not decoded frame by frame. `--thorough` samples 2 fps when a cut may sit inside a GOP.
2. A 30-second density floor, so a static stretch still appears.
3. Question hits in the transcript are kept first.
4. 32×32 pixel dedup.
5. Farthest-point thinning to the budget, so the last minute survives.
6. One JPEG grid, timestamps burned into the cells when a font is available.
7. A transcript excerpt around those timestamps. The full text stays on disk.

If scene detection hits its time limit, the manifest says `PARTIAL`. An empty cut list is never reported as a clean success.

## MCP

stdio server: `node dist/server.js`

| Tool | What the model gets |
|---|---|
| `watch` | One sheet for the whole file. Budget 1–12, default 9. |
| `detail` | One sheet for a window in seconds. Budget 1–6. |

```json
{
  "mcpServers": {
    "llm-video-vision": {
      "command": "node",
      "args": ["dist/server.js"]
    }
  }
}
```

Run that with the working directory set to this repo, or pass the absolute path to `dist/server.js`. Agent hosts that follow skills can also load [skills/watch-video/SKILL.md](skills/watch-video/SKILL.md).

Hosts that cannot display an MCP image still have the files. The manifest lists every frame path.

## Requirements

- Node.js 20+
- `ffmpeg` and `ffprobe` on `PATH`
- `yt-dlp` for `http(s)` URLs. Playlists are refused. Downloads are capped at 720p and cached next to the session.

Captions are preferred over speech-to-text. Pass `--lang es,en` (or the MCP `languages` array) and a manual track in the first language wins, including `es-419` style prefixes. Local Whisper is not bundled. The study behind that choice is [docs/research/upstream-claude-video-vision.md](docs/research/upstream-claude-video-vision.md).

## Develop

```bash
npm install
npm test
npm run build
```

## License

MIT. The approach is informed by [jordanrendric/claude-video-vision](https://github.com/jordanrendric/claude-video-vision). This repository is an original implementation, not a fork.
