// Query layer: golden-fixture drift gate, ledger semantics, and the
// materialized cache against DynamoDB Local (docker).
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { execSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { CreateTableCommand, DynamoDBClient } from "@aws-sdk/client-dynamodb";

process.env.TABLE_NAME = "birdcount-data-test";
const PORT = 8124; // sync.test.ts runs its own container on 8123 in parallel
const ENDPOINT = `http://localhost:${PORT}`;

const { docClient } = await import("../src/dynamo.js");
const { sync, SCOPE } = await import("../src/sync.js");
const { computeSummary, queryObservations, refreshLedger, resetLedgerCache, validateRange } =
  await import("../src/ledger.js");

const fixtures = join(dirname(fileURLToPath(import.meta.url)), "../../../bird-count-schema/fixtures");
const loadJson = (p: string) => JSON.parse(readFileSync(join(fixtures, p), "utf8"));

const observationFixtures = readdirSync(join(fixtures, "valid"))
  .filter((n) => n.startsWith("observation"))
  .map((n) => loadJson(join("valid", n)));

const goldenCases: Array<{
  name: string;
  response: {
    begin: string;
    end: string;
    totalIndividuals: number;
    totalSpecies: number;
    species: Array<{ taxonId: string; count: number; lastObservedAt: string }>;
  };
}> = loadJson("derived/summary-cases.json");

// -- Golden drift gate: same cases the iOS conformance tests check --

describe("computeSummary golden cases", () => {
  for (const c of goldenCases) {
    it(`matches derived/summary-cases.json#${c.name}`, () => {
      const { begin, end } = c.response;
      expect(computeSummary(observationFixtures, begin, end)).toEqual(c.response);
    });
  }
});

// -- Ledger semantics units (ported from the retiring web ledger tests) --

function rec(id: string, over: Record<string, unknown> = {}) {
  return {
    id,
    taxonId: "amecro",
    begin: "2026-07-01T14:00:00Z",
    end: "2026-07-01T14:00:00Z",
    count: 5,
    ...over,
  };
}

const JULY = { begin: "2026-07-01T00:00:00Z", end: "2026-07-01T23:59:59Z" };

describe("computeSummary semantics", () => {
  it("excludes orphans (parentId present, parent absent)", () => {
    const orphan = rec("DEAD0000-0000-4000-8000-000000000001", {
      parentId: "MISSING0-0000-4000-8000-000000000000",
      taxonId: "norcar",
    });
    const summary = computeSummary([rec("A"), orphan], JULY.begin, JULY.end);
    expect(summary.species.map((s) => s.taxonId)).toEqual(["amecro"]);
  });

  it("in-range parent carries out-of-range children", () => {
    const child = rec("B", { parentId: "A", count: -3, begin: "2026-08-01T00:00:00Z", end: "2026-08-01T00:00:00Z" });
    const summary = computeSummary([rec("A"), child], JULY.begin, JULY.end);
    expect(summary.species).toEqual([
      { taxonId: "amecro", count: 2, lastObservedAt: "2026-08-01T00:00:00Z" },
    ]);
  });

  it("adjustment zeroing its parent hides the species", () => {
    const child = rec("B", { parentId: "A", count: -5 });
    const summary = computeSummary([rec("A"), child], JULY.begin, JULY.end);
    expect(summary.totalSpecies).toBe(0);
    expect(summary.species).toEqual([]);
  });

  it("range filter applies to top-level records only", () => {
    // window covers only the child; parent (and so its subtree) excluded
    const child = rec("B", { parentId: "A", begin: "2026-07-01T18:00:00Z", end: "2026-07-01T18:00:00Z" });
    const summary = computeSummary([rec("A"), child], "2026-07-01T16:00:00Z", "2026-07-01T20:00:00Z");
    expect(summary.species).toEqual([]);
  });

  it("sorts by count desc then taxonId asc", () => {
    const summary = computeSummary(
      [rec("A", { taxonId: "zonlei" }), rec("B", { taxonId: "amecro" }), rec("C", { taxonId: "norcar", count: 9 })],
      JULY.begin,
      JULY.end,
    );
    expect(summary.species.map((s) => s.taxonId)).toEqual(["norcar", "amecro", "zonlei"]);
  });
});

describe("queryObservations", () => {
  function stored(id: string, over: Record<string, unknown> = {}) {
    // minimal StoredObservation shape for the pure query fn
    return {
      ...rec(id, over),
      pk: SCOPE,
      sk: `obs#${id}`,
      observerSub: "sub",
      updatedAt: 1782914400000,
      serverUpdatedAt: 1,
      createdAt: 1,
      schemaVersion: 2,
    } as never;
  }

  it("returns top-level records with recursive netCount, storage fields stripped", () => {
    const res = queryObservations(
      [stored("A"), stored("B", { parentId: "A", count: -3 })],
      { begin: JULY.begin, end: JULY.end, limit: 50 },
    );
    expect(res.items).toHaveLength(1);
    expect(res.items[0].netCount).toBe(2);
    expect(res.items[0].record.id).toBe("A");
    expect(res.items[0].record).not.toHaveProperty("pk");
    expect(res.items[0].record).not.toHaveProperty("serverUpdatedAt");
  });

  it("filters by taxonId", () => {
    const res = queryObservations(
      [stored("A"), stored("B", { taxonId: "norcar" })],
      { begin: JULY.begin, end: JULY.end, taxonId: "norcar", limit: 50 },
    );
    expect(res.items.map((i) => i.record.id)).toEqual(["B"]);
  });

  it("pages newest-first through an opaque cursor to completion", () => {
    const records = Array.from({ length: 5 }, (_, n) =>
      stored(`0000000${n}`, { begin: `2026-07-01T0${n}:00:00Z`, end: `2026-07-01T0${n}:00:00Z` }),
    );
    const seen: string[] = [];
    let cursor: string | undefined;
    for (;;) {
      const page = queryObservations(records, { begin: JULY.begin, end: JULY.end, limit: 2, cursor });
      seen.push(...page.items.map((i) => i.record.id));
      if (!page.hasMore) {
        expect(page.cursor).toBe("");
        break;
      }
      cursor = page.cursor;
    }
    expect(seen).toEqual(["00000004", "00000003", "00000002", "00000001", "00000000"]);
  });
});

describe("validateRange", () => {
  it("accepts a valid range", () => {
    expect(validateRange(JULY.begin, JULY.end)).toBeUndefined();
  });
  it("rejects missing, malformed, and inverted params", () => {
    expect(validateRange(undefined, JULY.end)).toMatch(/required/);
    expect(validateRange("not-a-date", JULY.end)).toMatch(/begin/);
    expect(validateRange(JULY.end, JULY.begin)).toMatch(/<=/);
  });
});

// -- Materialized cache against DynamoDB Local --

const doc = docClient(ENDPOINT);
let containerId = "";

function syncReq(changes: unknown[]) {
  return {
    schemaVersion: 2,
    clientId: "D7E8F9A0-B1C2-4D3E-9F4A-5B6C7D8E9F0A",
    changes,
  } as Parameters<typeof sync>[1];
}

beforeAll(async () => {
  containerId = execSync(`docker run -d --rm -p ${PORT}:8000 amazon/dynamodb-local`).toString().trim();
  const client = new DynamoDBClient({
    endpoint: ENDPOINT,
    region: "local",
    credentials: { accessKeyId: "local", secretAccessKey: "local" },
  });
  for (let i = 0; ; i++) {
    try {
      await client.send(
        new CreateTableCommand({
          TableName: "birdcount-data-test",
          BillingMode: "PAY_PER_REQUEST",
          AttributeDefinitions: [
            { AttributeName: "pk", AttributeType: "S" },
            { AttributeName: "sk", AttributeType: "S" },
            { AttributeName: "serverUpdatedAt", AttributeType: "N" },
          ],
          KeySchema: [
            { AttributeName: "pk", KeyType: "HASH" },
            { AttributeName: "sk", KeyType: "RANGE" },
          ],
          GlobalSecondaryIndexes: [
            {
              IndexName: "changes",
              KeySchema: [
                { AttributeName: "pk", KeyType: "HASH" },
                { AttributeName: "serverUpdatedAt", KeyType: "RANGE" },
              ],
              Projection: { ProjectionType: "ALL" },
            },
          ],
        }),
      );
      break;
    } catch (err) {
      if (i > 40) throw err;
      await new Promise((r) => setTimeout(r, 250));
    }
  }
}, 60_000);

afterAll(() => {
  if (containerId) execSync(`docker stop ${containerId}`);
});

describe("refreshLedger (DynamoDB Local)", () => {
  it("cold-loads the fixture graph and reproduces the golden summaries", async () => {
    resetLedgerCache();
    await sync(doc, syncReq(observationFixtures), "sub-a");

    const ledger = await refreshLedger(doc, SCOPE);
    expect(ledger.records.size).toBe(observationFixtures.length);
    for (const c of goldenCases) {
      const { begin, end } = c.response;
      expect(computeSummary(ledger.records.values(), begin, end)).toEqual(c.response);
    }
  });

  it("delta-refreshes: a record pushed after the cold load appears on the next query", async () => {
    const before = await refreshLedger(doc, SCOPE);
    const beforeCursor = before.cursor;

    await sync(doc, syncReq([rec("33333333-3333-4333-8333-333333333333", {
      taxonId: "sonspa",
      count: 4,
      observer: "test",
      status: "completed",
      updatedAt: 1782914400000,
    })]), "sub-a");

    const after = await refreshLedger(doc, SCOPE);
    expect(after.cursor).toBeGreaterThan(beforeCursor);

    const summary = computeSummary(after.records.values(), JULY.begin, JULY.end);
    expect(summary.species.find((s) => s.taxonId === "sonspa")?.count).toBe(4);
  });
});
