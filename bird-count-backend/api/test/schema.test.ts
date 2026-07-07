// Drift gate: the handler's ajv validation must accept every valid shared
// fixture and reject every invalid one.
import { describe, expect, it } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parseSyncRequest } from "../src/validate.js";

const fixtures = join(dirname(fileURLToPath(import.meta.url)), "../../../bird-count-schema/fixtures");

// Wrap a bare observation fixture in a minimal sync request.
function asSyncBody(observation: unknown): string {
  return JSON.stringify({
    schemaVersion: 2,
    clientId: "D7E8F9A0-B1C2-4D3E-9F4A-5B6C7D8E9F0A",
    changes: [observation],
  });
}

describe("shared fixtures through request validation", () => {
  for (const name of readdirSync(join(fixtures, "valid"))) {
    const raw = readFileSync(join(fixtures, "valid", name), "utf8");
    if (name.startsWith("observation")) {
      it(`accepts valid/${name}`, () => {
        expect(parseSyncRequest(asSyncBody(JSON.parse(raw))).request).toBeDefined();
      });
    } else if (name.startsWith("sync-request")) {
      it(`accepts valid/${name}`, () => {
        expect(parseSyncRequest(raw).request).toBeDefined();
      });
    }
  }

  for (const name of readdirSync(join(fixtures, "invalid"))) {
    const raw = readFileSync(join(fixtures, "invalid", name), "utf8");
    const body = name.startsWith("sync-request") ? raw : asSyncBody(JSON.parse(raw));
    it(`rejects invalid/${name}`, () => {
      expect(parseSyncRequest(body).errors).toBeDefined();
    });
  }

  it("rejects garbage", () => {
    expect(parseSyncRequest("not json").errors).toBeDefined();
    expect(parseSyncRequest(undefined).errors).toBeDefined();
  });
});
