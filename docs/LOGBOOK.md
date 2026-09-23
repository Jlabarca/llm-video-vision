# LOGBOOK.md — Session History

> Append-only. Never edit previous entries. Each session adds one block.
> Four sections: **Accomplished** / **Decisions** / **Blockers** / **Next**. Tests optional fifth section.
> Decisions is the gold — "X over Y because Z" — that's what survives compaction.

---

## 2026-09-23 — Born the repo and shipped the budgeted watch path

**Accomplished:**

- `ware new llm-video-vision` created the public repo `jlabarca/llm-video-vision` and installed the ghostdev methodology.
- Wrote the upstream study at [research/upstream-claude-video-vision.md](research/upstream-claude-video-vision.md).
- Implemented `watch` / `detail` / `lvw`: keyframe scene pass, 30s floor, pixel dedup, one contact sheet, caption-first excerpt.

**Decisions:**

- Image budget is 9 by default and hard-capped at 12, returned as one grid, because a uniform dump either truncates the start of a long video or floods the context window. Study: the upstream `-frames:v 100` path.
- Scene detection runs on keyframes at 320px and reports `PARTIAL` on timeout, because a native-resolution filter pass is what makes upstream return an empty scene list after 600s.
- Captions win over bundled Whisper, and the language list is caller-supplied, because upstream hardcodes English and then pays for a transcript the platform already had.

**Blockers:**

- `ware new` verify (S11) exited 1 on pre-existing workspace doctor findings (`asset-inbox`, `scratch`, `Siigo`, `stratum-2.0`). The new repo itself was created and pushed.
- No live ffmpeg run yet. Unit tests cover selection, parsing, and the watch orchestration with fake extractors.

**Next:**

- M0.5 — run `lvw` on a real file and a URL.
- M0.6 — a small public eval set.

---
