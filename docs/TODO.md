# TODO.md — Active Sprint

> Current sprint: **M0 — budgeted watch**
> Sprint goal: one `watch` call covers a whole video with at most 12 images.
> Reset each sprint cycle. Completed sprints roll up into [CONTEXT.md](CONTEXT.md).

---

## M0 — budgeted watch

- [x] M0.1 — Study upstream and record it at [research/upstream-claude-video-vision.md](research/upstream-claude-video-vision.md) — evidence: that file
- [x] M0.2 — Select frames across the whole duration inside a hard budget — evidence: `tests/select.test.ts`
- [x] M0.3 — Pixel dedup, caption language choice, scene-cut parser — evidence: `tests/captions.test.ts`, `tests/parse.test.ts`
- [x] M0.4 — `watch` returns one sheet and labels a timed-out analysis `PARTIAL` — evidence: `tests/watch.test.ts`
- [ ] M0.5 — Run `lvw` on a real local file and a URL, and confirm the grid is one image
- [ ] M0.6 — Publish the eval set (slides, fast cut, screencast, one-second event, long 4K)

---
