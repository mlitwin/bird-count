#!/usr/bin/env node
// Validates every fixture: fixtures/valid/* must pass, fixtures/invalid/* must fail.
// Fixture-to-schema mapping is by filename prefix (see schemaFor).
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";
import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const load = (p) => JSON.parse(readFileSync(join(root, p), "utf8"));

const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);
for (const f of readdirSync(join(root, "schemas"))) {
  ajv.addSchema(load(join("schemas", f)));
}

const BASE = "https://birdcount.dev/schemas/";
function schemaFor(name) {
  if (name.startsWith("observation")) return BASE + "observation.schema.json";
  if (name.startsWith("sync-request")) return BASE + "sync.schema.json#/$defs/SyncRequest";
  if (name.startsWith("sync-response")) return BASE + "sync.schema.json#/$defs/SyncResponse";
  if (name.startsWith("payload")) return BASE + "payload.schema.json";
  if (name.startsWith("location")) return BASE + "location.schema.json";
  // unprefixed invalid fixtures (missing-id, bad-status, …) are observation shapes
  return BASE + "observation.schema.json";
}

let failures = 0;
for (const [dir, expectValid] of [["valid", true], ["invalid", false]]) {
  for (const name of readdirSync(join(root, "fixtures", dir)).sort()) {
    const validate = ajv.getSchema(schemaFor(name));
    const ok = validate(load(join("fixtures", dir, name)));
    if (ok === expectValid) {
      console.log(`  ok  ${dir}/${name}`);
    } else {
      failures++;
      console.error(`FAIL  ${dir}/${name} — expected ${expectValid ? "valid" : "invalid"}, got ${ok ? "valid" : "invalid"}`);
      if (!ok) console.error(ajv.errorsText(validate.errors, { separator: "\n        " }));
    }
  }
}

if (failures) {
  console.error(`\n${failures} fixture(s) failed`);
  process.exit(1);
}
console.log("\nAll fixtures behave as expected.");
