#!/usr/bin/env node
// suggest-compact: PreToolUse hook that nudges the user to /clear or split into
// a subagent when the session transcript is approaching the context budget.
//
// Profile: strict only (per ADR 0003 §1). minimal/standard exit immediately.
//
// Token estimate is intentionally rough. We divide transcript bytes by 2:
//   - English: ~1 token / 4 bytes → this overestimates ~2x (earlier warning).
//   - Japanese: ~1 token / 3 bytes UTF-8 → still slightly overestimates.
// Early-warning bias is intentional for an advisory hook. JSONL overhead in the
// transcript adds further inflation. Override via $SUGGEST_COMPACT_THRESHOLD.

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

const estTokens = Math.floor(bytes / 2);
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
