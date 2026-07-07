#!/usr/bin/env node
// Generates TypeScript types for the backend from the JSON Schemas.
// Output is checked in; CI regenerates and fails on diff.
// Usage: node scripts/generate-ts.mjs [outFile]
import { compileFromFile } from "json-schema-to-typescript";
import { mkdirSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const outFile = process.argv[2] ?? join(root, "..", "bird-count-backend", "api", "src", "generated", "types.ts");

const banner = `/* eslint-disable */
/**
 * GENERATED FILE — do not edit.
 * Source: bird-count-schema/schemas/ (version ${String(await import("node:fs").then(fs => fs.readFileSync(join(root, "VERSION"), "utf8"))).trim()})
 * Regenerate: node bird-count-schema/scripts/generate-ts.mjs
 */
`;

const opts = {
  cwd: join(root, "schemas"),
  bannerComment: "",
  additionalProperties: false,
  style: { singleQuote: true },
};

const parts = [];
for (const file of ["observation.schema.json", "sync.schema.json", "payload.schema.json"]) {
  parts.push(await compileFromFile(join(root, "schemas", file), opts));
}

// Each schema $refs location/observation, so compiled outputs repeat shared
// interfaces; keep the first occurrence of each `export interface X` block.
const seen = new Set();
const deduped = parts
  .join("\n")
  .split(/(?=^export )/m)
  .filter((block) => {
    const m = block.match(/^export (?:interface|type) (\w+)/);
    if (!m) return true;
    if (seen.has(m[1])) return false;
    seen.add(m[1]);
    return true;
  })
  .join("");

mkdirSync(dirname(outFile), { recursive: true });
writeFileSync(outFile, banner + deduped);
console.log(`wrote ${outFile}`);
