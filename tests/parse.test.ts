import { describe, expect, it } from "vitest";
import { parseCues, parseProbe, parseScdet } from "../src/parse.js";
import { escapeLavfiPath, sceneArgs, gridShape } from "../src/ffmpeg.js";

describe("parse", () => {
  it("reads duration, size, and audio from ffprobe JSON", () => {
    const probe = parseProbe(JSON.stringify({
      format: { duration: "12.5" },
      streams: [
        { codec_type: "video", width: 1920, height: 1080, codec_name: "h264" },
        { codec_type: "audio", codec_name: "aac" },
      ],
    }));
    expect(probe).toMatchObject({ duration: 12.5, width: 1920, height: 1080, hasAudio: true, codec: "h264" });
  });

  it("keeps a cut and ignores a low score that is not a cut", () => {
    const text = [
      "frame:0 pts:0 pts_time:0",
      "lavfi.scd.score=1.5",
      "frame:10 pts:100 pts_time:4.0",
      "lavfi.scd.score=18.2",
      "lavfi.scd.time=4.0",
      "frame:11 pts:110 pts_time:4.4",
      "lavfi.scd.score=3.0",
      "lavfi.scd.time=4.4",
    ].join("\n");
    expect(parseScdet(text, 10)).toEqual([{ time: 4, score: 18.2 }]);
  });

  it("parses an srt cue with hours and milliseconds", () => {
    const cues = parseCues("1\n01:02:03,500 --> 01:02:04,000\nHello <b>there</b>\n");
    expect(cues[0].text).toBe("Hello there");
    expect(cues[0].start).toBeCloseTo(3723.5);
  });
});

describe("ffmpeg args", () => {
  it("builds a keyframe scene pass with no output path inside the filter", () => {
    const args = sceneArgs("C:/videos/demo.mp4", false);
    expect(args).toContain("-skip_frame");
    expect(args.join(" ")).toContain("scdet=threshold=10");
    expect(args.join(" ")).not.toContain("file=");
  });

  it("escapes a Windows drive letter for lavfi", () => {
    expect(escapeLavfiPath("C:\\Users\\a.txt")).toBe("C\\\\:/Users/a.txt");
  });

  it("packs 9 frames as a 3 by 3 sheet and refuses a 13th cell", () => {
    expect(gridShape(9)).toEqual({ cols: 3, rows: 3 });
    expect(gridShape(5)).toEqual({ cols: 3, rows: 2 });
    expect(gridShape(12)).toEqual({ cols: 4, rows: 3 });
  });
});
