#!/usr/bin/env node
// suggest-compact: PreToolUse hook that nudges the user to /clear or split into
// a subagent when the session transcript is approaching the context budget.
//
// Profile: strict only (per ADR 0003 §1). minimal/standard exit immediately.
//
// Token estimate is intentionally rough — transcript bytes / 4 — and biases
// high because JSONL overhead is included. Treat it as an approximate signal,
// not an exact count. Override the threshold with $SUGGEST_COMPACT_THRESHOLD.

import { statSync } from "node:fs";

const profile = process.env.HOOK_PROFILE ?? "standard";
if (profile !== "strict") process.exit(0);

const threshold = Number(process.env.SUGGEST_COMPACT_THRESHOLD ?? 140000);

let raw = "";
process.stdin.setEncoding("utf8");
for await (const chunk of process.stdin) raw += chunk;

let input;
try {
  input = JSON.parse(raw);
} catch {
  process.exit(0);
}

const transcript = input?.transcript_path;
if (!transcript) process.exit(0);

let bytes;
try {
  bytes = statSync(transcript).size;
} catch {
  process.exit(0);
}

const estTokens = Math.floor(bytes / 4);
if (estTokens < threshold) process.exit(0);

const msg =
  `[suggest-compact] Estimated context usage ~${estTokens.toLocaleString()} tokens ` +
  `(threshold ${threshold.toLocaleString()}). Consider /clear, or delegate the ` +
  `next exploration to an investigator/planner subagent to keep main context lean.`;

process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: msg,
    },
  }),
);
