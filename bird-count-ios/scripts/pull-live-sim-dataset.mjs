#!/usr/bin/env node
/**
 * One-time (manual, infrequent) pull of a realistic observation dataset from
 * the bird-count-backend API, for use as a committed Live Simulator Testing
 * fixture. See docs/live-simulator-testing-plan.md.
 *
 * Not run automatically and not part of CI — re-run by hand whenever a
 * larger/fresher fixture is needed, then commit the resulting JSON under
 * bird-count-ios/data/.
 *
 * Requires the same env vars as bird-count-backend's e2e suite (see
 * bird-count-backend/api/test/e2e/run.ts and e2e-dev.env / e2e-prod.env):
 *   E2E_API_URL, E2E_TOKEN_ENDPOINT, E2E_CLIENT_ID, E2E_CLIENT_SECRET, E2E_RESOURCE_SERVER
 *
 * Run from bird-count-backend so 1Password-backed env injection is available:
 *   cd bird-count-backend
 *   op run --env-file e2e-dev.env -- node ../bird-count-ios/scripts/pull-live-sim-dataset.mjs \
 *     --out ../bird-count-ios/data/live-sim-dataset.json
 */
import { writeFile } from "node:fs/promises";

const REQUIRED_ENV = ["E2E_API_URL", "E2E_TOKEN_ENDPOINT", "E2E_CLIENT_ID", "E2E_CLIENT_SECRET", "E2E_RESOURCE_SERVER"];
for (const v of REQUIRED_ENV) {
  if (!process.env[v]) {
    console.error(`Missing env var: ${v} (see script header for how to run this)`);
    process.exit(1);
  }
}

const API_URL = process.env.E2E_API_URL.replace(/\/v\d+\/?$/, "").replace(/\/$/, "");
const TOKEN_ENDPOINT = process.env.E2E_TOKEN_ENDPOINT;
const CLIENT_ID = process.env.E2E_CLIENT_ID;
const CLIENT_SECRET = process.env.E2E_CLIENT_SECRET;
const RESOURCE_SERVER = process.env.E2E_RESOURCE_SERVER;

const args = process.argv.slice(2);
const outIdx = args.indexOf("--out");
const outPath = outIdx >= 0 ? args[outIdx + 1] : null;
if (!outPath) {
  console.error("Usage: pull-live-sim-dataset.mjs --out <path.json> [--limit N] [--max N]");
  process.exit(1);
}
const limitIdx = args.indexOf("--limit");
const pageLimit = limitIdx >= 0 ? Number(args[limitIdx + 1]) : 200;
const maxIdx = args.indexOf("--max");
// The API's shared partition pools observations across all users and can be
// far larger than any single realistic fixture needs (seen: 200k+ and still
// growing). Default cap keeps the pull bounded and the fixture a reasonable
// size; raise with --max if a larger dataset is specifically needed.
const maxRecords = maxIdx >= 0 ? Number(args[maxIdx + 1]) : 20000;

async function fetchToken() {
  const creds = Buffer.from(`${CLIENT_ID}:${CLIENT_SECRET}`).toString("base64");
  const res = await fetch(TOKEN_ENDPOINT, {
    method: "POST",
    headers: {
      Authorization: `Basic ${creds}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      scope: `${RESOURCE_SERVER}/sync`,
    }).toString(),
  });
  if (!res.ok) throw new Error(`Token fetch failed: ${res.status} ${await res.text()}`);
  const { access_token } = await res.json();
  return access_token;
}

async function pullPage(token, hwm) {
  const qs = new URLSearchParams({ limit: String(pageLimit) });
  if (hwm !== undefined) qs.set("hwm", String(hwm));
  const res = await fetch(`${API_URL}/v1/observations?${qs}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error(`Pull failed: ${res.status} ${await res.text()}`);
  return res.json();
}

async function main() {
  const token = await fetchToken();
  const all = [];
  let hwm = undefined;
  let hasMore = true;
  while (hasMore && all.length < maxRecords) {
    const page = await pullPage(token, hwm);
    all.push(...(page.changes ?? []));
    hasMore = Boolean(page.hasMore);
    hwm = page.tripSequenceHighWater;
    process.stderr.write(`Pulled ${all.length} observations so far...\n`);
  }
  console.error(`\nPulled ${all.length} observations total${all.length >= maxRecords ? ` (stopped at --max ${maxRecords})` : ""}.`);
  await writeFile(outPath, JSON.stringify(all, null, 2));
  console.error(`Wrote ${outPath}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
