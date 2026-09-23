---
name: watch-video
description: Use when the user gives a video file or a video URL, or asks what happens in a video. Prefer the watch tool. Do not extract your own frames.
---

# Watch a video

`llm-video-vision` returns one contact sheet and a short transcript excerpt.
The sheet already spans the whole file. Default budget is 9 frames, hard cap 12.

1. Call `watch` once with the path or URL and the user's question.
   Pass `languages` when the video is not English (`["es", "en"]`).
2. Read the manifest, then the grid, left to right, top to bottom.
   The manifest lists each cell's timestamp and why it was kept.
3. Answer from that. Cite timestamps from the sheet.
4. Call `detail` only for a window the sheet does not resolve.
   Keep that budget at or below 6. Do not call it "just in case".
5. A line that says `PARTIAL` means scene detection was cut off.
   Say so if the missing region matters, and retry that region with `detail`
   or `watch` plus `thorough: true`.

The full transcript, the frames, and `grid.jpg` are paths in the manifest.
Read a frame file only when a cell is too small to settle the question.
