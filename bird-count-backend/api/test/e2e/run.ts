/**
 * E2E test suite for the bird-count sync API.
 *
 * Requires env vars:
 *   E2E_API_URL         — API Gateway invoke URL (no trailing slash)
 *   E2E_TOKEN_ENDPOINT  — Cognito /oauth2/token URL
 *   E2E_CLIENT_ID       — M2M app client ID
 *   E2E_CLIENT_SECRET   — M2M app client secret
 *
 * Run via: make e2e   (injects vars from terraform output + 1Password)
 */

const API_URL = process.env.E2E_API_URL!;
const TOKEN_ENDPOINT = process.env.E2E_TOKEN_ENDPOINT!;
const CLIENT_ID = process.env.E2E_CLIENT_ID!;
const CLIENT_SECRET = process.env.E2E_CLIENT_SECRET!;
// Resource server identifier is the `aud` in client-credentials tokens.
// Format: https://{project}-{env}-api.internal  (set by Terraform auth module)
const RESOURCE_SERVER = process.env.E2E_RESOURCE_SERVER!;

for (const v of ["E2E_API_URL", "E2E_TOKEN_ENDPOINT", "E2E_CLIENT_ID", "E2E_CLIENT_SECRET", "E2E_RESOURCE_SERVER"]) {
  if (!process.env[v]) { console.error(`Missing env var: ${v}`); process.exit(1); }
}

// ── auth ────────────────────────────────────────────────────────────────────

async function fetchToken(): Promise<string> {
  const creds = Buffer.from(`${CLIENT_ID}:${CLIENT_SECRET}`).toString("base64");
  const res = await fetch(TOKEN_ENDPOINT, {
    method: "POST",
    headers: {
      "Authorization": `Basic ${creds}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      scope: `${RESOURCE_SERVER}/sync`,
    }).toString(),
  });
  if (!res.ok) throw new Error(`Token fetch failed: ${res.status} ${await res.text()}`);
  const { access_token } = await res.json() as { access_token: string };
  return access_token;
}

// ── API helpers ──────────────────────────────────────────────────────────────

async function callSync(token: string, body: unknown) {
  const res = await fetch(`${API_URL}/v1/sync`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}

async function callPull(token: string, params: Record<string, string | number> = {}) {
  const qs = new URLSearchParams(Object.entries(params).map(([k, v]) => [k, String(v)]));
  const res = await fetch(`${API_URL}/v1/observations?${qs}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return { status: res.status, body: await res.json() };
}

function obs(id: string, over: Record<string, unknown> = {}) {
  return {
    id,
    taxonId: "amecro",
    begin: "2026-01-15T10:00:00Z",
    end: "2026-01-15T10:30:00Z",
    count: 1,
    observer: "e2e-test",
    status: "completed",
    updatedAt: 1752566400000,
    ...over,
  };
}

function syncReq(changes: unknown[], extra: Record<string, unknown> = {}) {
  return { schemaVersion: 2, clientId: "E2E00000-0000-4E2E-8E2E-E2E000000000", changes, ...extra };
}

// ── test runner ──────────────────────────────────────────────────────────────

let passed = 0;
let failed = 0;

function assert(label: string, condition: boolean, detail?: unknown) {
  if (condition) {
    console.log(`  ✓ ${label}`);
    passed++;
  } else {
    console.error(`  ✗ ${label}`, detail ?? "");
    failed++;
  }
}

// ── test cases ───────────────────────────────────────────────────────────────

async function run() {
  const token = await fetchToken();
  console.log("Token obtained.\n");

  // IDs scoped to this run so parallel runs don't collide.
  const run = Date.now().toString(36);
  const id1 = `11111111-E2E0-4000-8000-${run.padStart(12, "0")}`;
  const id2 = `22222222-E2E0-4000-8000-${run.padStart(12, "0")}`;
  const id3 = `33333333-E2E0-4000-8000-${run.padStart(12, "0")}`;

  // ── 1. New client: push assigns observationNumber ──────────────────────────
  console.log("1. New client push (with HWM)");
  {
    const { status, body } = await callSync(token, syncReq([obs(id1), obs(id2)], { serverSyncedObservationNumberHWM: 0 }));
    assert("status 200", status === 200, status);
    const a = body.applied as Array<{ id: string; result: string; observationNumber?: number }>;
    assert("two applied entries", a.length === 2, a.length);
    assert("id1 result=applied", a[0]?.result === "applied");
    assert("id1 has observationNumber", typeof a[0]?.observationNumber === "number", a[0]);
    assert("id2 result=applied", a[1]?.result === "applied");
    assert("id2 observationNumber > id1", (a[1]?.observationNumber ?? 0) > (a[0]?.observationNumber ?? 0));
    assert("tripSequenceHighWater present", typeof body.tripSequenceHighWater === "number", body);
    console.log(`   observationNumbers: ${a[0]?.observationNumber}, ${a[1]?.observationNumber}  hwm: ${body.tripSequenceHighWater}`);
  }

  // ── 2. Legacy client: push without HWM still works ──────────────────────────
  console.log("\n2. Legacy client push (no HWM)");
  {
    const { status, body } = await callSync(token, syncReq([obs(id3)]));
    assert("status 200", status === 200, status);
    const a = body.applied as Array<{ result: string }>;
    assert("applied result=applied", a[0]?.result === "applied");
    assert("no tripSequenceHighWater on legacy path", body.tripSequenceHighWater === undefined, body.tripSequenceHighWater);
  }

  // ── 3. Stale push rejected ──────────────────────────────────────────────────
  console.log("\n3. Stale push (older updatedAt)");
  {
    const stale = obs(id1, { updatedAt: 1752566400000 - 1000, observer: "stale-writer" });
    const { status, body } = await callSync(token, syncReq([stale]));
    assert("status 200", status === 200, status);
    assert("result=stale", body.applied[0]?.result === "stale", body.applied[0]);
  }

  // ── 4. Noop re-upload returns existing observationNumber ───────────────────
  console.log("\n4. Noop re-upload (same updatedAt)");
  {
    const { status, body } = await callSync(token, syncReq([obs(id1)], { serverSyncedObservationNumberHWM: 0 }));
    assert("status 200", status === 200, status);
    assert("result=applied (noop)", body.applied[0]?.result === "applied", body.applied[0]);
    assert("observationNumber returned on noop", typeof body.applied[0]?.observationNumber === "number", body.applied[0]);
  }

  // ── 5. HWM pull returns records in ascending order ─────────────────────────
  console.log("\n5. HWM pull (hwm=0)");
  {
    const { status, body } = await callPull(token, { hwm: 0 });
    assert("status 200", status === 200, status);
    const nums = (body.changes as Array<{ observationNumber?: number }>)
      .map((c) => c.observationNumber)
      .filter((n): n is number => n !== undefined);
    assert("changes have observationNumbers", nums.length > 0, nums.length);
    const sorted = [...nums].sort((a, b) => a - b);
    assert("ascending order", JSON.stringify(nums) === JSON.stringify(sorted), nums);
    assert("tripSequenceHighWater present", typeof body.tripSequenceHighWater === "number", body);
  }

  // ── 6. Legacy pull (no hwm) still works ────────────────────────────────────
  console.log("\n6. Legacy pull (no hwm)");
  {
    const { status, body } = await callPull(token, { since: "0" });
    assert("status 200", status === 200, status);
    assert("changes returned", Array.isArray(body.changes), body);
    assert("no tripSequenceHighWater on legacy pull", body.tripSequenceHighWater === undefined, body.tripSequenceHighWater);
  }

  // ── 7. Cross-client: legacy upload visible via HWM pull ────────────────────
  console.log("\n7. Cross-client visibility");
  {
    // id3 was uploaded by the legacy client above; check it appears in HWM pull
    const { body } = await callPull(token, { hwm: 0 });
    const ids = (body.changes as Array<{ id: string }>).map((c) => c.id);
    assert("legacy-uploaded id3 visible via HWM pull", ids.includes(id3), ids.filter(id => id.includes("33333333")));
  }

  // ── summary ─────────────────────────────────────────────────────────────────
  console.log(`\n${"─".repeat(40)}`);
  console.log(`${passed + failed} checks: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

run().catch((err) => { console.error(err); process.exit(1); });
