// Sync push/pull against DynamoDB Local (docker).
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { execSync } from "node:child_process";
import { CreateTableCommand, DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { GetCommand } from "@aws-sdk/lib-dynamodb";


process.env.TABLE_NAME = "birdcount-data-test";
process.env.SEQ_TABLE_NAME = "birdcount-seq-test";
// Settle horizon off by default so push-then-pull tests see their writes immediately.
process.env.PULL_SETTLE_MS = "0";
const PORT = 8123;
const ENDPOINT = `http://localhost:${PORT}`;

const { docClient, putObservation } = await import("../src/dynamo.js");
const { sync, pull, SCOPE } = await import("../src/sync.js");
const { tripSeqKey, getSeq, guardedIncr, raiseOnlySet } = await import("../src/seq.js");

const doc = docClient(ENDPOINT);
let containerId = "";

function obs(id: string, over: Record<string, unknown> = {}) {
  return {
    id,
    taxonId: "amecro",
    begin: "2026-07-01T14:00:00Z",
    end: "2026-07-01T14:00:00Z",
    count: 1,
    observer: "test",
    status: "completed" as const,
    updatedAt: 1782914400000,
    ...over,
  };
}

function req(changes: unknown[], cursor?: string) {
  return {
    schemaVersion: 2,
    clientId: "D7E8F9A0-B1C2-4D3E-9F4A-5B6C7D8E9F0A",
    ...(cursor !== undefined ? { cursor } : {}),
    changes,
  } as Parameters<typeof sync>[1];
}

beforeAll(async () => {
  containerId = execSync(
    `docker run -d --rm -p ${PORT}:8000 amazon/dynamodb-local`,
  ).toString().trim();

  const client = new DynamoDBClient({
    endpoint: ENDPOINT,
    region: "local",
    credentials: { accessKeyId: "local", secretAccessKey: "local" },
  });
  // DynamoDB Local takes a moment to accept connections
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
            { AttributeName: "observationNumber", AttributeType: "N" },
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
            {
              IndexName: "gsi_observationNumber",
              KeySchema: [
                { AttributeName: "pk", KeyType: "HASH" },
                { AttributeName: "observationNumber", KeyType: "RANGE" },
              ],
              Projection: { ProjectionType: "ALL" },
            },
          ],
        }),
      );
      await client.send(
        new CreateTableCommand({
          TableName: "birdcount-seq-test",
          BillingMode: "PAY_PER_REQUEST",
          AttributeDefinitions: [{ AttributeName: "pk", AttributeType: "S" }],
          KeySchema: [{ AttributeName: "pk", KeyType: "HASH" }],
        }),
      );
      break;
    } catch (err) {
      if (i > 40) throw err;
      await new Promise((r) => setTimeout(r, 250));
    }
  }
  await raiseOnlySet(doc, tripSeqKey("shared"), 0);
}, 60_000);

afterAll(() => {
  if (containerId) execSync(`docker stop ${containerId}`);
});

describe("sync push + pull", () => {
  it("pushes records and pulls them from cursor 0", async () => {
    const res = await sync(doc, req([obs("11111111-1111-4111-8111-111111111111"), obs("22222222-2222-4222-8222-222222222222")]), "sub-a");
    expect(res.applied).toEqual([
      { id: "11111111-1111-4111-8111-111111111111", result: "applied", observationNumber: expect.any(Number) },
      { id: "22222222-2222-4222-8222-222222222222", result: "applied", observationNumber: expect.any(Number) },
    ]);

    const pulled = await pull(doc, "0");
    expect(pulled.changes.map((c) => c.id).sort()).toEqual([
      "11111111-1111-4111-8111-111111111111",
      "22222222-2222-4222-8222-222222222222",
    ]);
    expect(pulled.hasMore).toBe(false);
    expect(Number(pulled.cursor)).toBeGreaterThan(0);
  });

  it("location backfill with newer updatedAt overwrites; delta returns just it", async () => {
    const before = await pull(doc, "0");
    const backfilled = obs("11111111-1111-4111-8111-111111111111", {
      updatedAt: 1782914500000,
      location: {
        latitude: 38.44,
        longitude: -122.71,
        horizontalAccuracy: 5,
        timestamp: "2026-07-01T14:00:02Z",
      },
    });
    const res = await sync(doc, req([backfilled], before.cursor), "sub-a");
    expect(res.applied[0].result).toBe("applied");

    const delta = await pull(doc, before.cursor);
    const updated = delta.changes.filter((c) => c.location !== undefined);
    expect(updated).toHaveLength(1);
    expect(updated[0].id).toBe("11111111-1111-4111-8111-111111111111");
    expect(updated[0].updatedAt).toBe(1782914500000);
  });

  it("stale push returns 'stale' and does not overwrite", async () => {
    const stale = obs("11111111-1111-4111-8111-111111111111", { updatedAt: 1782914000000, observer: "stale-writer" });
    const res = await sync(doc, req([stale]), "sub-b");
    expect(res.applied[0].result).toBe("stale");

    const all = await pull(doc, "0");
    const record = all.changes.find((c) => c.id === "11111111-1111-4111-8111-111111111111")!;
    expect(record.observer).toBe("test");
    expect(record.updatedAt).toBe(1782914500000);
  });

  it("negative-count adjustment child round-trips with parentId intact", async () => {
    const child = obs("33333333-3333-4333-8333-333333333333", {
      parentId: "11111111-1111-4111-8111-111111111111",
      count: -1,
      updatedAt: 1782914600000,
    });
    const res = await sync(doc, req([child]), "sub-a");
    expect(res.applied[0].result).toBe("applied");

    const all = await pull(doc, "0");
    const got = all.changes.find((c) => c.id === "33333333-3333-4333-8333-333333333333")!;
    expect(got.count).toBe(-1);
    expect(got.parentId).toBe("11111111-1111-4111-8111-111111111111");
  });

  it("legacy record without updatedAt gets the end-time backfill", async () => {
    const legacy = obs("44444444-4444-4444-8444-444444444444", { updatedAt: undefined });
    delete (legacy as Record<string, unknown>).updatedAt;
    await sync(doc, req([legacy]), "sub-a");

    const all = await pull(doc, "0");
    const got = all.changes.find((c) => c.id === "44444444-4444-4444-8444-444444444444")!;
    expect(got.updatedAt).toBe(Date.parse("2026-07-01T14:00:00Z"));
  });

  it("sync response cursor advances past pushed records", async () => {
    const before = await pull(doc, "0");
    const res = await sync(doc, req([obs("55555555-5555-4555-8555-555555555555")], before.cursor), "sub-a");
    const next = await pull(doc, res.cursor);
    // overlap window may re-deliver, but nothing beyond the cursor is missing
    expect(next.changes.every((c) => c.id !== "unknown")).toBe(true);
    expect(Number(res.cursor)).toBeGreaterThanOrEqual(Number(before.cursor));
  });

  it("stress: 500+ records push in chunks and paginate to completion", async () => {
    const batches = Array.from({ length: 5 }, (_, batch) =>
      Array.from({ length: 100 }, (_, i) =>
        obs(`99999999-0000-4000-8000-${String(batch * 100 + i).padStart(12, "0")}`),
      ),
    );
    for (const batch of batches) {
      const res = await sync(doc, req(batch), "sub-stress");
      expect(res.applied).toHaveLength(100);
      expect(res.applied.every((a) => a.result === "applied")).toBe(true);
    }

    // Walk the full delta from cursor 0 in pages of 200.
    let cursor = "0";
    const seen = new Set<string>();
    let pages = 0;
    for (;;) {
      const page = await pull(doc, cursor);
      pages++;
      page.changes.forEach((c) => seen.add(c.id));
      if (!page.hasMore) break;
      expect(page.cursor).not.toBe(cursor); // cursor must always advance
      cursor = page.cursor;
      expect(pages).toBeLessThan(20); // no pathological re-delivery loops
    }
    const stressSeen = [...seen].filter((id) => id.startsWith("99999999")).length;
    expect(stressSeen).toBe(500);
  }, 60_000);

  it("sync cursor does not leapfrog undelivered pages (two-device field bug)", async () => {
    // Device A is fully caught up.
    let cursorA = "0";
    for (;;) {
      const p = await pull(doc, cursorA);
      cursorA = p.cursor;
      if (!p.hasMore) break;
    }

    // Device B pushes 250 records — more than one PULL_LIMIT page.
    const bIds = Array.from({ length: 250 }, (_, i) =>
      `77777777-0000-4000-8000-${String(i).padStart(12, "0")}`,
    );
    for (let i = 0; i < bIds.length; i += 100) {
      await sync(doc, req(bIds.slice(i, i + 100).map((id) => obs(id))), "sub-b");
    }

    // Device A syncs one new record, then drains hasMore pages the way
    // CloudSyncService does: from the sync response's cursor.
    const res = await sync(
      doc,
      req([obs("88888888-8888-4888-8888-888888888888")], cursorA),
      "sub-a",
    );
    const seen = new Set(res.changes.map((c) => c.id));
    let cursor = res.cursor;
    let hasMore = res.hasMore;
    while (hasMore) {
      const page = await pull(doc, cursor);
      page.changes.forEach((c) => seen.add(c.id));
      expect(page.cursor).not.toBe(cursor);
      cursor = page.cursor;
      hasMore = page.hasMore;
    }

    // Every one of device B's records must reach device A.
    expect(bIds.filter((id) => seen.has(id))).toHaveLength(250);
  }, 60_000);

  it("paginates with hasMore", async () => {
    const many = Array.from({ length: 12 }, (_, i) =>
      obs(`66666666-0000-4000-8000-${String(i).padStart(12, "0")}`),
    );
    await sync(doc, req(many), "sub-a");
    const page = await pull(doc, "0", undefined, 5);
    expect(page.changes).toHaveLength(5);
    expect(page.hasMore).toBe(true);

    // walk pages to completion
    let cursor = "0";
    const seen = new Set<string>();
    for (let i = 0; i < 20; i++) {
      const p = await pull(doc, cursor, undefined, 5);
      p.changes.forEach((c) => seen.add(c.id!));
      if (!p.hasMore && cursor === p.cursor) break;
      cursor = p.cursor;
    }
    expect(seen.size).toBeGreaterThanOrEqual(17);
  });
});

async function stored(id: string) {
  const res = await doc.send(
    new GetCommand({ TableName: "birdcount-data-test", Key: { pk: SCOPE, sk: `obs#${id}` }, ConsistentRead: true }),
  );
  return res.Item!;
}

async function withSettleMs<T>(ms: number, fn: () => Promise<T>): Promise<T> {
  process.env.PULL_SETTLE_MS = String(ms);
  try {
    return await fn();
  } finally {
    process.env.PULL_SETTLE_MS = "0";
  }
}

// Directly land an item with a chosen number, as a concurrent sync would.
async function landNumbered(id: string, n: number, numberedAt: number, updatedAt = 1782914400000) {
  const now = Date.now();
  return putObservation(doc, {
    ...obs(id, { updatedAt }),
    pk: SCOPE,
    sk: `obs#${id}`,
    observerSub: "sub-x",
    serverUpdatedAt: numberedAt,
    createdAt: now,
    schemaVersion: 2,
    observationNumber: n,
    numberedAt,
  });
}

describe("single-phase numbering", () => {
  it("writes observationNumber and numberedAt with the record", async () => {
    const id = "a1a1a1a1-0000-4000-8000-000000000001";
    const res = await sync(doc, req([obs(id)]), "sub-a");
    const item = await stored(id);
    expect(item.observationNumber).toBe(res.applied[0].observationNumber);
    expect(typeof item.numberedAt).toBe("number");
  });

  it("stale push burns a number but leaves the stored record and number alone", async () => {
    const id = "a1a1a1a1-0000-4000-8000-000000000002";
    const first = await sync(doc, req([obs(id)]), "sub-a");
    const res = await sync(doc, req([obs(id, { updatedAt: 1782914400000 - 1 })]), "sub-b");
    expect(res.applied[0]).toEqual({ id, result: "stale" });
    expect((await stored(id)).observationNumber).toBe(first.applied[0].observationNumber);
  });

  it("noop re-upload returns the stored number", async () => {
    const id = "a1a1a1a1-0000-4000-8000-000000000003";
    const first = await sync(doc, req([obs(id)]), "sub-a");
    const again = await sync(doc, req([obs(id)]), "sub-a");
    expect(again.applied[0].observationNumber).toBe(first.applied[0].observationNumber);
  });

  it("newer edit whose number is not above the stored one renumbers and retries", async () => {
    // Stands in for: our sync allocates n, a concurrent writer allocates a higher number for an
    // older version and lands first. Our newer version must not land with the lower number, or
    // readers already past the stored number would never see it. Here the stored item already
    // holds the number our first allocation will get (c+1), forcing one renumber round.
    const id = "a1a1a1a1-0000-4000-8000-000000000004";
    const c = (await getSeq(doc, tripSeqKey(SCOPE)))!;
    expect(await landNumbered(id, c + 1, Date.now(), 1782914400000)).toBe("written");
    const res = await sync(doc, req([obs(id, { updatedAt: 1782914400000 + 1 })]), "sub-a");
    expect(res.applied[0]).toEqual({ id, result: "applied", observationNumber: c + 2 });
    const item = await stored(id);
    expect(item.observationNumber).toBe(c + 2);
    expect(item.updatedAt).toBe(1782914400000 + 1);
  });
});

describe("pull settle horizon", () => {
  it("holds back unsettled records without advancing the HWM cursor", async () => {
    const base = await pull(doc, undefined, 0, 10_000);
    const hwm = Number(base.cursor);
    const id = "b2b2b2b2-0000-4000-8000-000000000001";
    await sync(doc, req([obs(id)]), "sub-a");

    const held = await withSettleMs(60_000, () => pull(doc, undefined, hwm));
    expect(held.changes.map((c) => c.id)).not.toContain(id);
    expect(held.cursor).toBe(String(hwm));
    expect(held.hasMore).toBe(false);

    const released = await pull(doc, undefined, hwm);
    expect(released.changes.map((c) => c.id)).toContain(id);
  });

  it("holds back unsettled records on the legacy timestamp path", async () => {
    const base = await pull(doc, "0", undefined, 10_000);
    const id = "b2b2b2b2-0000-4000-8000-000000000002";
    await sync(doc, req([obs(id)]), "sub-a");

    const held = await withSettleMs(60_000, () => pull(doc, base.cursor, undefined));
    expect(held.changes.map((c) => c.id)).not.toContain(id);
    expect(held.cursor).toBe(base.cursor);

    const released = await pull(doc, base.cursor, undefined);
    expect(released.changes.map((c) => c.id)).toContain(id);
  });

  it("out-of-order landing: a later number cannot carry the cursor past an earlier in-flight one", async () => {
    const base = await pull(doc, undefined, 0, 10_000);
    const hwm = Number(base.cursor);
    const c = (await getSeq(doc, tripSeqKey(SCOPE)))!;
    const early = "b2b2b2b2-0000-4000-8000-000000000003";
    const late = "b2b2b2b2-0000-4000-8000-000000000004";
    // Two concurrent syncs allocate c+1 (early) then c+2 (late); late lands first.
    await guardedIncr(doc, tripSeqKey(SCOPE));
    await guardedIncr(doc, tripSeqKey(SCOPE));
    const allocatedAt = Date.now();
    await landNumbered(late, c + 2, allocatedAt);

    // Device pulls while c+1 is still in flight: nothing is released, cursor stays put.
    const during = await withSettleMs(10_000, () => pull(doc, undefined, hwm));
    expect(during.changes.map((c) => c.id)).not.toContain(late);
    expect(Number(during.cursor)).toBe(hwm);

    await landNumbered(early, c + 1, allocatedAt);
    // After the horizon passes, both arrive in order.
    const after = await pull(doc, undefined, hwm);
    const ids = after.changes.map((c) => c.id);
    expect(ids.indexOf(early)).toBeGreaterThanOrEqual(0);
    expect(ids.indexOf(early)).toBeLessThan(ids.indexOf(late));
  });

  it("without the horizon the same race skips the earlier record (documents the bug)", async () => {
    const base = await pull(doc, undefined, 0, 10_000);
    const hwm = Number(base.cursor);
    const c = (await getSeq(doc, tripSeqKey(SCOPE)))!;
    const early = "b2b2b2b2-0000-4000-8000-000000000005";
    const late = "b2b2b2b2-0000-4000-8000-000000000006";
    await guardedIncr(doc, tripSeqKey(SCOPE));
    await guardedIncr(doc, tripSeqKey(SCOPE));
    await landNumbered(late, c + 2, Date.now());
    const during = await pull(doc, undefined, hwm); // PULL_SETTLE_MS=0
    expect(Number(during.cursor)).toBe(c + 2);
    await landNumbered(early, c + 1, Date.now());
    const after = await pull(doc, undefined, Number(during.cursor));
    expect(after.changes.map((c) => c.id)).not.toContain(early);
  });
});

describe("seq counter", () => {
  it("guardedIncr refuses an unseeded key", async () => {
    const key = tripSeqKey("unseeded");
    expect(await guardedIncr(doc, key)).toBe(-1);
    expect(await getSeq(doc, key)).toBeNull();
  });

  it("raiseOnlySet only raises, and guardedIncr counts up from the seed", async () => {
    const key = tripSeqKey("raise");
    expect(await raiseOnlySet(doc, key, 10)).toBe(true);
    expect(await raiseOnlySet(doc, key, 5)).toBe(false);
    expect(await raiseOnlySet(doc, key, 10)).toBe(false);
    expect(await getSeq(doc, key)).toBe(10);
    expect(await guardedIncr(doc, key)).toBe(11);
    expect(await guardedIncr(doc, key)).toBe(12);
  });

  it("concurrent increments hand out distinct numbers", async () => {
    const key = tripSeqKey("concurrent");
    await raiseOnlySet(doc, key, 0);
    const ns = await Promise.all(Array.from({ length: 20 }, () => guardedIncr(doc, key)));
    expect(new Set(ns).size).toBe(20);
    expect(Math.max(...ns)).toBe(20);
  });
});
