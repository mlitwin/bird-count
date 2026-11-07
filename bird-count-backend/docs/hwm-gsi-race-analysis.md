# Pull ordering race: analysis, fix, and the strict alternative

**Status (2026-11-07):** the single-phase numbering and settle-horizon fixes
(options B and A below) are implemented. The strict transactional log
(option F) is designed here but not built. This document replaces the
earlier three-stage plan, whose client-side Stage 2 turned out not to work
(see [Rejected options](#rejected-options)).

## Symptom

On a shared group count (several devices syncing to the `"shared"` scope),
observations received from *other* devices sometimes vanish from a device's
log for good. A device's own records always stay, because it created them
locally. The records are intact and numbered in DynamoDB; the device's pull
cursor just moved past them before they became visible. Solo users never see
this. The web viewer's summary cache could miss records the same way.

## What is and isn't strongly consistent

| Component | Guarantee | Used for |
|---|---|---|
| Base table (`pk`/`sk`) | Strongly consistent per-item reads and conditional writes | `putObservation` LWW put; source of truth |
| Seq table counter (`tripSeqKey`) | Atomic, serialized conditional `ADD`; hands out each number exactly once | `guardedIncr` allocates `observationNumber` |
| GSI `gsi_observationNumber` | **Eventually consistent**; no `ConsistentRead`; propagation order across items not guaranteed | HWM pull (`queryByNumber`) |
| GSI `changes` (`serverUpdatedAt`) | Same | Legacy timestamp pull (`queryChanges`), web ledger (`refreshLedger`) |

Moving the counter from Valkey to DynamoDB (2026-11) kept these guarantees.
The one new capability is that counter and data now share a store, so they
can be updated in a single transaction. Option F relies on that.

## Root cause

The **order numbers are allocated** is not the **order records become
visible** to readers. Two things cause the mismatch:

1. **Two-phase numbering (before the fix).** `sync()` saved the record
   without a number, then allocated a number, then stamped it with a second
   `UpdateItem`. Concurrent syncs could finish those steps in any order.
2. **Concurrent writes land and propagate out of order.** Even when the
   number is written with the record, two syncs that allocate *n* and *n+1*
   can land in the opposite order, and GSI propagation can reorder them
   again.

Every pull cursor treats "highest number seen" as "everything below has
been seen" (iOS: `advanceServerSyncedHWM` from the returned records;
server: `maxSeen` in `pull`). Once a reader sees *n+1* before *n*, its
next query is `observationNumber > n+1`, so *n* is never returned.

```
t0  Sync A allocates 5 for X.
t1  Sync B allocates 6 for Y; Y lands and reaches the GSI first.
t2  Device C pulls with hwm=4: the GSI shows 6, not 5. C's HWM becomes 6.
t3  X (5) becomes visible.
t4+ C queries "> 6" forever after; X is unreachable for C.
```

The legacy timestamp path and the web ledger have the same flaw with
`serverUpdatedAt`: stamps are taken before the put, concurrent syncs land in
any order, and the `changes` GSI is eventually consistent.

### Gaps in the number sequence are normal

Any fix that assumes numbers are contiguous will fail, because missing
numbers are routine:

- **Edits renumber.** A newer version replaces the item with a fresh, higher
  number; the old number never appears in the GSI again.
- **Burned numbers.** A stale or noop put after allocation wastes its number.
  An SDK retry of the (non-idempotent) `ADD` can also skip one.
- **Failed legacy stamps.** These are repaired by assigning a new number.

A reader can't tell "missing for good" from "not visible yet" by looking at
the numbers. That is why this design delays what readers see (A), or reads a
consistent log (F), rather than having clients check for missing numbers.

## Implemented fix

### B. Single-phase numbering (`sync.ts`, `dynamo.ts`)

`sync()` now allocates the number first and writes it, with `numberedAt`
(server clock just after allocation), in the same conditional put. An item is
never visible without its number. Results:

- **written**: new record, or strictly newer `updatedAt` *and* a higher
  number than the stored one.
- **renumber**: newer `updatedAt`, but the stored number is ≥ ours (a
  concurrent writer allocated later and landed first). Landing anyway would
  hide this version from readers already past the stored number, so `sync()`
  allocates again and retries (up to 5 attempts).
- **stale** / **noop**: the allocated number is burned (a harmless gap). A
  noop returns the stored number. A legacy item that was stored without a
  number is repaired with the just-allocated one (`setObservationNumber`,
  which also sets `numberedAt`).

### A. Settle horizon (`pullSettleMs`, `settledPrefix`)

Pulls release only records that are at least `PULL_SETTLE_MS` old (default
10 000 ms):

- **HWM pull:** walks the page in number order and stops at the first item
  with `numberedAt > now - horizon`. Items without `numberedAt` (numbered
  before this change) count as settled.
- **Legacy pull:** the same, using `serverUpdatedAt`.
- **Web ledger:** caches unsettled rows so the summary stays fresh, but its
  cursor stops before them, so the next refresh reads them again.

Held-back records are left out of the response, and `hasMore` is false when
the page is cut short. This matters because iOS advances its HWM from the
records it receives, not from `cursor`. Queries stay strictly after the
cursor: this is a delayed cutoff, not an overlap window, so pagination is
unaffected.

**Guarantee.** Numbers are allocated in time order. If *m* is released, it
was allocated at least `PULL_SETTLE_MS` ago, so every *k < m* was allocated
before that. *k* can therefore be skipped only if allocating and landing it,
plus GSI propagation, took longer than the horizon. A sync that dies partway
is safe: its record never lands with *k*, and a later re-upload gets a new,
higher number. The leftover risk is a single write stalling for 10 s or more
(e.g. an SDK retry storm), or server clocks differing by a meaningful
fraction of the horizon. Neither is a realistic concern at this volume.

**Cost.** Other devices see a new record up to `PULL_SETTLE_MS` later. In
practice that adds at most one sync cycle; iOS syncs 30 s after a local
edit and 3 s after coming to the foreground or back online. The pushing
device gets its own numbers immediately in `applied`.

**Clients.** No wire change, and old app versions are covered automatically.
`tripSequenceHighWater` is still the raw counter, so it can be ahead of what
has been released. Treat it as informational; the client doesn't use it.

## Option F: strict transactional log (designed, not built)

Build F to get a hard guarantee with no timing assumption, or if traffic
grows enough that a 10 s tail matters.

**Storage.** A new append-only table `birdcount-log-<env>` with `pk` = scope
and `sk` = `n` (number). Each entry holds the record key, or a full
snapshot, which makes the log the ledger's event stream.

**Write (per change).** Read the counter `c` (consistent), then one
`TransactWriteItems` with three parts:
1. Counter: `SET seq = c+1` only if `seq = c`.
2. Record: put with `observationNumber = c+1`, using the LWW condition and
   `ReturnValuesOnConditionCheckFailure: ALL_OLD`.
3. Log: put `n = c+1` only if `attribute_not_exists`.

If the counter condition fails or the transaction conflicts, re-read and
retry (rare at this volume). If the record condition fails, classify it as
stale or noop from `ALL_OLD`. No number is burned, because the whole
transaction is cancelled.

**Why this is strict.** Transaction *c+1* can only commit after transaction
*c* has set the counter to *c*. Records therefore commit in number order, and
a number exists only if its record and log entry exist.

**Pull.**
1. Read the counter `C` (consistent).
2. Query the log with `ConsistentRead` for `hwm < n ≤ C`, with a page limit.
3. `BatchGetItem` the records (consistent), or use the snapshots.
4. Skip entries whose record now carries a different (higher) number;
   that version is returned at its own number.

Everything ≤ `C` committed before step 1, so a consistent query returns all
of it. No GSI is involved, and the cursor can't pass an unseen number. The
web ledger can switch to a number cursor too, and the settle horizon can be
removed.

**Migration.**
- Backfill log entries for existing numbered items with a new
  `seqMaintenance` action (~14k in prod).
- Deploy the write path, then the read path.
- `gsi_observationNumber` can be retired later.

**Cost.**
- A transactional write costs 2× the write units, across three items.
- The pull adds one `BatchGet` per page.
- Total is still cents per month.
- Effort: write and pull rewrite, a new table, the backfill, tests.
  Medium.

## Rejected options

| Option | Why not |
|---|---|
| Old Stage 2: client checks for missing numbers, plus a `tripSequenceHighWater` catch-up check | The catch-up check misses the race: in the timeline above, C's HWM (6) equals the counter (6). The missing-number check stalls on every normal gap (edits, burned numbers) until a retry limit runs out, which amounts to a client-side horizon. It also needs an iOS release, and old clients stay broken. |
| Client re-pulls the last K numbers each sync | Works in practice, but iOS-only (old clients not fixed) and probabilistic. A is the server-side version of the same idea. |
| Periodic full resync (e.g. at the end of a count) | Repairs after the fact rather than preventing. Still a reasonable cheap backstop to add to iOS later. |
| API Lambda reserved concurrency = 1 (serialize writers) | Fixes write order but not GSI reordering; queues and throttles all requests. |
| Server-side overlap window (re-send recent records) | Breaks pagination (see sync-architecture.md); A gets the same benefit by delaying the cutoff instead. |

## Verification

- **`sync.test.ts`, single-phase numbering:**
  - the number and `numberedAt` are written with the record;
  - stale and noop handling;
  - the renumber retry (first allocation rejected, record lands at the next
    number).
- **`sync.test.ts`, settle horizon:**
  - held-back records on the HWM and legacy paths, with the cursor not
    advancing;
  - out-of-order landing with the horizon (no skip, released in order);
  - the same race with the horizon off (shows the skip).
- **`query.test.ts`:** the ledger caches unsettled rows but keeps its cursor
  before them.
- **e2e (`test/e2e/run.ts`):** step 1b checks that just-pushed records are
  held back. The run then waits out the horizon before the visibility
  checks.
- **Field check:** after a busy group count, run `make seq-status` and spot
  check that devices' record counts match `/v1/summary`.

## Recovering already-affected devices

Records lost to this race before the fix are intact on the server. Running
`resyncAll` on an affected device resets its cursors and HWM and pulls
everything again.
