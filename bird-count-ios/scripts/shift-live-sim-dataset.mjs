#!/usr/bin/env node
/**
 * Shifts (and optionally filters) a pulled live-sim observation dataset
 * (array of ObservationRecordDTO JSON, as produced by pull-live-sim-dataset.mjs)
 * so the most recent observation lands on "today" — preserving realistic
 * distribution/clustering — and, optionally, keeps only a trailing window
 * of the dataset to reproduce shorter-list scenarios without a separate
 * fixture. See docs/live-simulator-testing-plan.md.
 *
 * Usage:
 *   node shift-live-sim-dataset.mjs --in data/live-sim-dataset.json --out /tmp/shifted.json [--days N]
 *
 * --days N   Keep only observations whose (post-shift) end date falls within
 *            the last N days. Omit to shift the full dataset unfiltered.
 */
import { readFile, writeFile } from "node:fs/promises";

const args = process.argv.slice(2);
function argValue(flag) {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : null;
}

const inPath = argValue("--in");
const outPath = argValue("--out");
const days = argValue("--days") ? Number(argValue("--days")) : null;

if (!inPath || !outPath) {
  console.error("Usage: shift-live-sim-dataset.mjs --in <path.json> --out <path.json> [--days N]");
  process.exit(1);
}

const DATE_FIELDS = ["begin", "end"];

async function main() {
  const raw = JSON.parse(await readFile(inPath, "utf8"));

  const latestEndMs = raw.reduce((max, o) => Math.max(max, Date.parse(o.end)), 0);
  const shiftMs = Date.now() - latestEndMs;

  let shifted = raw.map((o) => {
    const copy = { ...o };
    for (const field of DATE_FIELDS) {
      copy[field] = new Date(Date.parse(o[field]) + shiftMs).toISOString();
    }
    // updatedAt is wire-encoded as epoch millis (see ObservationRecordDTO), not ISO8601.
    if (typeof o.updatedAt === "number") {
      copy.updatedAt = o.updatedAt + shiftMs;
    }
    return copy;
  });

  if (days !== null) {
    const cutoffMs = Date.now() - days * 24 * 60 * 60 * 1000;
    shifted = shifted.filter((o) => Date.parse(o.end) >= cutoffMs);
  }

  await writeFile(outPath, JSON.stringify(shifted, null, 2));
  console.error(`Shifted ${raw.length} records by ${(shiftMs / 86400000).toFixed(1)} days` +
    (days !== null ? `, kept ${shifted.length} within the last ${days} days` : "") +
    ` -> ${outPath}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
