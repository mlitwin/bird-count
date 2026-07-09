// ledger.test.mjs — unit tests for ledger.js
// Loads the golden fixtures from bird-count-schema/fixtures/valid/ directly,
// extending the schema drift-gate to the web viewer as a third consumer
// (alongside the backend's ajv validation and iOS SchemaConformanceTests).
//
// Run: npm test  (or: node --test test/ledger.test.mjs)

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';
import { buildTree, filterInRange, computeCounts, countsInRange } from '../js/ledger.js';

// -- Shared fixtures --

const FIXTURES = join(dirname(fileURLToPath(import.meta.url)), '../../bird-count-schema/fixtures/valid');
const loadFixture = name => JSON.parse(readFileSync(join(FIXTURES, `${name}.json`), 'utf8'));

// The valid fixtures form one three-level chain plus a separate root:
//   ROOT (amecro, +1, 2026-07-01)
//     └ CHILD (norcar, +3)
//         └ ADJUSTMENT (norcar, -3)
//   LEGACY (sonspa, +2, 2025-11-12) — separate root, earlier date
const ROOT       = loadFixture('observation-minimal');
const CHILD      = loadFixture('observation-full');
const ADJUSTMENT = loadFixture('observation-adjustment-child');
const LEGACY     = loadFixture('observation-legacy-v1');
const ALL_FIXTURES = [ROOT, CHILD, ADJUSTMENT, LEGACY];

// Sanity-check the graph shape the tests below rely on; fails loudly if the
// fixtures are restructured, rather than letting assertions mislead.
assert.equal(CHILD.parentId, ROOT.id, 'fixture drift: CHILD must be a child of ROOT');
assert.equal(ADJUSTMENT.parentId, CHILD.id, 'fixture drift: ADJUSTMENT must be a child of CHILD');
assert.equal(LEGACY.parentId, undefined, 'fixture drift: LEGACY must be a root');

// Synthetic: the fixtures have no orphan (parentId referencing an absent record)
const ORPHAN = {
  id: 'DEAD0000-0000-4000-8000-000000000001',
  parentId: 'MISSING0-0000-4000-8000-000000000000',
  taxonId: 'norcar',
  begin: '2026-07-01T14:00:00Z',
  end: '2026-07-01T14:00:00Z',
  count: 2,
};

const JULY_RANGE = { begin: '2026-07-01T00:00:00Z', end: '2026-07-01T23:59:59Z' }; // ROOT only
const OUT_RANGE  = { begin: '2026-06-01T00:00:00Z', end: '2026-06-30T23:59:59Z' }; // nothing
const ALL_RANGE  = { begin: '1970-01-01T00:00:00Z', end: '2026-12-31T23:59:59Z' }; // ROOT + LEGACY

// -- buildTree --

describe('buildTree', () => {
  it('roots contains only parentId-less records', () => {
    const { roots } = buildTree(ALL_FIXTURES);
    assert.deepEqual(roots.map(r => r.id).sort(), [ROOT.id, LEGACY.id].sort());
  });

  it('children are indexed under their parent, including grandchildren', () => {
    const { childrenByParent } = buildTree(ALL_FIXTURES);
    assert.equal(childrenByParent.get(ROOT.id)?.[0].id, CHILD.id);
    assert.equal(childrenByParent.get(CHILD.id)?.[0].id, ADJUSTMENT.id);
  });

  it('orphans (parentId present but parent absent) are excluded', () => {
    const { roots, childrenByParent } = buildTree([ROOT, ORPHAN]);
    assert.equal(roots.length, 1);
    assert.equal(childrenByParent.size, 0);
  });
});

// -- filterInRange --

describe('filterInRange', () => {
  it('includes a root whose interval overlaps the range', () => {
    const { roots } = buildTree([ROOT]);
    assert.equal(filterInRange(roots, JULY_RANGE).length, 1);
  });

  it('excludes a root entirely outside the range', () => {
    const { roots } = buildTree([ROOT]);
    assert.equal(filterInRange(roots, OUT_RANGE).length, 0);
  });

  it('filters each root independently', () => {
    const { roots } = buildTree(ALL_FIXTURES);
    assert.deepEqual(filterInRange(roots, JULY_RANGE).map(r => r.id), [ROOT.id]);
  });

  it('includes a root that starts before the range but ends within it', () => {
    const earlyStart = { ...ROOT, begin: '2026-06-30T23:00:00Z', end: '2026-07-01T01:00:00Z' };
    assert.equal(filterInRange([earlyStart], JULY_RANGE).length, 1);
  });

  it('includes a root that starts within range but ends after it', () => {
    const lateEnd = { ...ROOT, begin: '2026-07-01T23:00:00Z', end: '2026-07-02T01:00:00Z' };
    assert.equal(filterInRange([lateEnd], JULY_RANGE).length, 1);
  });
});

// -- computeCounts --

describe('computeCounts', () => {
  it('recurses the whole subtree; adjustment cancels its parent per taxon', () => {
    const { roots, childrenByParent } = buildTree([ROOT, CHILD, ADJUSTMENT]);
    const counts = computeCounts(roots, childrenByParent);
    assert.equal(counts.get(ROOT.taxonId), ROOT.count);
    // CHILD and ADJUSTMENT share a taxon and cancel: +3 + (-3)
    assert.equal(counts.get(CHILD.taxonId), CHILD.count + ADJUSTMENT.count);
  });

  it('preserves zero and negative totals (caller filters)', () => {
    const { roots, childrenByParent } = buildTree([ROOT, CHILD, ADJUSTMENT]);
    const counts = computeCounts(roots, childrenByParent);
    assert.equal(counts.get(CHILD.taxonId), 0);
    assert.equal(counts.has(CHILD.taxonId), true);
  });

  it('handles multiple top-level records with different taxa', () => {
    const { roots, childrenByParent } = buildTree([ROOT, LEGACY]);
    const counts = computeCounts(roots, childrenByParent);
    assert.equal(counts.get(ROOT.taxonId), ROOT.count);
    assert.equal(counts.get(LEGACY.taxonId), LEGACY.count);
  });

  it('children with a different taxonId than their parent contribute to their own taxon', () => {
    // CHILD (norcar) hangs under ROOT (amecro) in the fixture graph
    assert.notEqual(CHILD.taxonId, ROOT.taxonId);
    const { roots, childrenByParent } = buildTree([ROOT, CHILD]);
    const counts = computeCounts(roots, childrenByParent);
    assert.equal(counts.get(ROOT.taxonId), ROOT.count);
    assert.equal(counts.get(CHILD.taxonId), CHILD.count);
  });
});

// -- countsInRange (full pipeline) --

describe('countsInRange', () => {
  it('returns positive counts for in-range records, dropping cancelled taxa', () => {
    const counts = countsInRange(ALL_FIXTURES, JULY_RANGE);
    assert.equal(counts.get(ROOT.taxonId), ROOT.count);
    assert.equal(counts.has(CHILD.taxonId), false); // +3 -3 → hidden
    assert.equal(counts.has(LEGACY.taxonId), false); // out of range
  });

  it('all-time range includes every root', () => {
    const counts = countsInRange(ALL_FIXTURES, ALL_RANGE);
    assert.equal(counts.get(ROOT.taxonId), ROOT.count);
    assert.equal(counts.get(LEGACY.taxonId), LEGACY.count);
  });

  it('returns empty map for out-of-range data', () => {
    const counts = countsInRange(ALL_FIXTURES, OUT_RANGE);
    assert.equal(counts.size, 0);
  });

  it('excludes orphans from totals', () => {
    const counts = countsInRange([ROOT, ORPHAN], JULY_RANGE);
    assert.equal(counts.has(ORPHAN.taxonId), false);
    assert.equal(counts.get(ROOT.taxonId), ROOT.count);
  });

  it('in-range parent contributes full subtree even when child dates are outside range', () => {
    // Push CHILD's dates into August; ROOT (July, in range) still carries it
    const futureChild = { ...CHILD, begin: '2026-08-01T00:00:00Z', end: '2026-08-01T00:00:00Z' };
    const counts = countsInRange([ROOT, futureChild], JULY_RANGE);
    assert.equal(counts.get(CHILD.taxonId), CHILD.count);
  });

  it('swipe-delete pattern (adjustment zeroes parent) hides species from summary', () => {
    const deleteAdj = { ...ADJUSTMENT, parentId: ROOT.id, taxonId: ROOT.taxonId, count: -ROOT.count };
    const counts = countsInRange([ROOT, deleteAdj], JULY_RANGE);
    assert.equal(counts.has(ROOT.taxonId), false);
  });
});
