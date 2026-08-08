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

describe("iOS SyncRequestBody payloads", () => {
  it("accepts request with serverSyncedObservationNumberHWM=0", () => {
    const body = JSON.stringify({
      schemaVersion: 2,
      clientId: "D7E8F9A0-B1C2-4D3E-9F4A-5B6C7D8E9F0A",
      cursor: "0",
      serverSyncedObservationNumberHWM: 0,
      changes: [{
        id: "A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D",
        taxonId: "amecro",
        begin: "2026-08-07T20:00:00.000Z",
        end: "2026-08-07T21:00:00.000Z",
        count: 1,
        observer: "",
        status: "completed",
        updatedAt: 1754596800000,
      }],
    });
    expect(parseSyncRequest(body).request).toBeDefined();
  });

  it("accepts request with serverSyncedObservationNumberHWM=50 and empty changes", () => {
    const body = JSON.stringify({
      schemaVersion: 2,
      clientId: "D7E8F9A0-B1C2-4D3E-9F4A-5B6C7D8E9F0A",
      cursor: "1754596800000",
      serverSyncedObservationNumberHWM: 50,
      changes: [],
    });
    expect(parseSyncRequest(body).request).toBeDefined();
  });

  it("accepts request with location and HWM", () => {
    const body = JSON.stringify({
      schemaVersion: 2,
      clientId: "D7E8F9A0-B1C2-4D3E-9F4A-5B6C7D8E9F0A",
      cursor: "0",
      serverSyncedObservationNumberHWM: 0,
      changes: [{
        id: "A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D",
        taxonId: "amecro",
        begin: "2026-08-07T20:00:00.000Z",
        end: "2026-08-07T21:00:00.000Z",
        count: 1,
        observer: "user@example.com",
        status: "completed",
        updatedAt: 1754596800000,
        location: {
          latitude: 38.44,
          longitude: -122.71,
          horizontalAccuracy: 5.0,
          timestamp: "2026-08-07T20:00:00.000Z",
        },
      }],
    });
    expect(parseSyncRequest(body).request).toBeDefined();
  });
});
