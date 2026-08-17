#!/usr/bin/env node
// suggest-compact: PreToolUse hook that nudges the user to /clear or split into
// a subagent when the session is approaching the context budget.
// Profile: strict only (ADR 0003 §1). minimal/standard exit immediately.

import { closeSync, fstatSync, openSync, readSync } from 'node:fs';

const profile = process.env.HOOK_PROFILE ?? 'standard';
if (profile !== 'strict') process.exit(0);

function positiveNumber(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

const contextWindow = positiveNumber(process.env.SUGGEST_COMPACT_WINDOW, 1_000_000);
const threshold = positiveNumber(
  process.env.SUGGEST_COMPACT_THRESHOLD,
  Math.floor(contextWindow * 0.7),
);
const FIRST_TAIL_BYTES = 256 * 1024;
const MAX_TAIL_BYTES = 16 * 1024 * 1024;

function readTail(fd, size, span) {
  const start = Math.max(0, size - span);
  const buf = Buffer.alloc(size - start);
  readSync(fd, buf, 0, buf.length, start);
  const text = buf.toString('utf8');
  return start > 0 ? text.slice(text.indexOf('\n') + 1) : text;
}

function latestUsage(text) {
  const lines = text.split('\n');
  for (let i = lines.length - 1; i >= 0; i--) {
    if (!lines[i]) continue;
    let record;
    try {
      record = JSON.parse(lines[i]);
    } catch {
      continue;
    }
    if (record?.isSidechain) continue;
    const usage = record?.message?.usage;
    if (!usage) continue;
    return (
      (usage.input_tokens ?? 0) +
      (usage.cache_read_input_tokens ?? 0) +
      (usage.cache_creation_input_tokens ?? 0)
    );
  }
  return null;
}

let raw = '';
process.stdin.setEncoding('utf8');
for await (const chunk of process.stdin) raw += chunk;

let input;
try {
  input = JSON.parse(raw);
} catch {
  process.exit(0);
}

const transcript = input?.transcript_path;
if (!transcript) process.exit(0);

let used = null;
try {
  const fd = openSync(transcript, 'r');
  try {
    const { size } = fstatSync(fd);
    for (let span = FIRST_TAIL_BYTES; used === null; span *= 4) {
      used = latestUsage(readTail(fd, size, span));
      if (span >= size || span >= MAX_TAIL_BYTES) break;
    }
  } finally {
    closeSync(fd);
  }
} catch {
  process.exit(0);
}

if (used === null || used < threshold) process.exit(0);

const fmt = new Intl.NumberFormat('en-US').format;
const pct = Math.round((used / contextWindow) * 100);
const msg = `[suggest-compact] Context usage ~${fmt(used)} tokens (${pct}% of a ${fmt(contextWindow)} window, threshold ${fmt(threshold)}). Consider /clear, or delegate the next exploration to an investigator/planner subagent to keep main context lean.`;

process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      additionalContext: msg,
    },
  }),
);
