#!/usr/bin/env node
import { readFileSync } from "fs";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { createRuntime, sessionDir } from "./runtime.js";
import { watch } from "./watch.js";

const server = new McpServer({ name: "llm-video-vision", version: "0.1.0" });

const source = z.string().describe("Local video path or http(s) URL (yt-dlp, no playlists)");
const budget = z.number().int().min(1).max(12).optional().describe("Max frames packed into one contact sheet. Default 9.");
const question = z.string().optional().describe("What you need from the video. Biases which moments are kept.");
const languages = z.array(z.string()).optional().describe("Caption languages to prefer, in order. Example: ['es','en']");
const thorough = z.boolean().optional().describe("Sample 2 fps instead of keyframes. Slower. Use when a cut may hide inside a GOP.");

server.tool(
  "watch",
  "Watch a video with a hard image budget. Returns one contact sheet plus a short transcript excerpt. The sheet covers the whole timeline. Call detail only for a moment this sheet does not answer.",
  { source, budget, question, languages, thorough },
  async (args) => runTool(args),
);

server.tool(
  "detail",
  "Look at one short window. Returns one contact sheet of at most 6 frames. Use after watch, not instead of it.",
  {
    source,
    start: z.number().min(0).describe("Window start in seconds"),
    end: z.number().positive().describe("Window end in seconds"),
    budget: z.number().int().min(1).max(6).optional(),
    question,
    languages,
  },
  async (args) => runTool({ ...args, window: { start: args.start, end: args.end }, budget: args.budget ?? 6 }),
);

async function runTool(args: {
  source: string;
  budget?: number;
  question?: string;
  languages?: string[];
  thorough?: boolean;
  window?: { start: number; end: number };
}) {
  const workDir = sessionDir(args.window ? `${args.source}@${args.window.start}-${args.window.end}` : args.source);
  const result = await watch(
    {
      source: args.source,
      budget: args.budget,
      question: args.question,
      languages: args.languages ?? ["en"],
      thorough: args.thorough,
      workDir,
      window: args.window,
    },
    createRuntime(args.languages ?? ["en"]),
  );
  const content: Array<
    { type: "text"; text: string } | { type: "image"; data: string; mimeType: string }
  > = [{ type: "text", text: result.manifest }];
  if (result.gridPath) {
    content.push({
      type: "image",
      data: readFileSync(result.gridPath).toString("base64"),
      mimeType: "image/jpeg",
    });
  }
  return { content };
}

const transport = new StdioServerTransport();
await server.connect(transport);
