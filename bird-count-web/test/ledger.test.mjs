// ledger.test.mjs — unit tests for ledger.js
// Uses fixture data matching bird-count-schema/fixtures/valid/ IDs exactly,
// extending the drift-gate to the web viewer as a third consumer.
//
// Run: npm test  (or: node --test test/ledger.test.mjs)

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { buildTree, filterInRange, computeCounts, countsInRange } from '../js/ledger.js';

// -- Fixtures (mirror bird-count-schema/fixtures/valid/) --

const PARENT = {
  id: 'A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D',
  taxonId: 'amecro',
  begin: '2026-07-01T14:00:00Z',
  end: '2026-07-01T14:00:00Z',
  count: 5,
};

// matches observation-adjustment-child.json
const ADJUSTMENT = {
  id: 'C0FFEE00-1111-4222-8333-444455556666',
  parentId: 'A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D',
  taxonId: 'amecro',
  begin: '2026-07-01T14:10:00Z',
  end: '2026-07-01T14:10:00Z',
  count: -3,
};

const ORPHAN = {
  id: 'DEAD0000-0000-4000-8000-000000000001',
  parentId: 'MISSING0-0000-4000-8000-000000000000',
  taxonId: 'norcar',
  begin: '2026-07-01T14:00:00Z',
  end: '2026-07-01T14:00:00Z',
  count: 2,
};

// A second top-level record with a different taxon
const SECOND = {
  id: '7B1E9F2A-3C4D-4E5F-8A9B-0C1D2E3F4A5B',
  taxonId: 'norcar',
  begin: '2026-07-01T14:00:00Z',
  end: '2026-07-01T14:00:00Z',
  count: 1,
};

const IN_RANGE  = { begin: '2026-07-01T00:00:00Z', end: '2026-07-01T23:59:59Z' };
const OUT_RANGE = { begin: '2026-06-01T00:00:00Z', end: '2026-06-30T23:59:59Z' };

// -- buildTree --

describe('buildTree', () => {
  it('roots contains only parentId-less records', () => {
    const { roots } = buildTree([PARENT, ADJUSTMENT]);
    assert.equal(roots.length, 1);
    assert.equal(roots[0].id, PARENT.id);
  });

  it('children are indexed under their parent', () => {
    const { childrenByParent } = buildTree([PARENT, ADJUSTMENT]);
    assert.equal(childrenByParent.get(PARENT.id)?.length, 1);
    assert.equal(childrenByParent.get(PARENT.id)[0].id, ADJUSTMENT.id);
  });

  it('orphans (parentId present but parent absent) are excluded', () => {
    const { roots, childrenByParent } = buildTree([PARENT, ORPHAN]);
    assert.equal(roots.length, 1);
    assert.equal(childrenByParent.size, 0);
  });

  it('multiple roots are all present', () => {
    const { roots } = buildTree([PARENT, SECOND]);
    assert.equal(roots.length, 2);
  });
});

// -- filterInRange --

describe('filterInRange', () => {
  it('includes a root whose interval overlaps the range', () => {
    const { roots } = buildTree([PARENT]);
    assert.equal(filterInRange(roots, IN_RANGE).length, 1);
  });

  it('excludes a root entirely outside the range', () => {
    const { roots } = buildTree([PARENT]);
    assert.equal(filterInRange(roots, OUT_RANGE).length, 0);
  });

  it('includes a root that starts before the range but ends within it', () => {
    const earlyStart = { ...PARENT, begin: '2026-06-30T23:00:00Z', end: '2026-07-01T01:00:00Z' };
    const { roots } = buildTree([earlyStart]);
    assert.equal(filterInRange(roots, IN_RANGE).length, 1);
  });

  it('includes a root that starts within range but ends after it', () => {
    const lateEnd = { ...PARENT, begin: '2026-07-01T23:00:00Z', end: '2026-07-02T01:00:00Z' };
    const { roots } = buildTree([lateEnd]);
    assert.equal(filterInRange(roots, IN_RANGE).length, 1);
  });
});

// -- computeCounts --

describe('computeCounts', () => {
  it('accumulates parent count + adjustment child count per taxon', () => {
    const { roots, childrenByParent } = buildTree([PARENT, ADJUSTMENT]);
    const counts = computeCounts(roots, childrenByParent);
    assert.equal(counts.get('amecro'), 2); // 5 + (-3)
  });

  it('preserves zero and negative totals (caller filters)', () => {
    const zero = { ...ADJUSTMENT, count: -5 };
    const { roots, childrenByParent } = buildTree([PARENT, zero]);
    const counts = computeCounts(roots, childrenByParent);
    assert.equal(counts.get('amecro'), 0); // 5 + (-5)
  });

  it('handles multiple top-level records with different taxa', () => {
    const { roots, childrenByParent } = buildTree([PARENT, SECOND]);
    const counts = computeCounts(roots, childrenByParent);
    assert.equal(counts.get('amecro'), 5);
    assert.equal(counts.get('norcar'), 1);
  });

  it('children with a different taxonId than their parent contribute to their own taxon', () => {
    const mixedChild = { ...ADJUSTMENT, taxonId: 'norcar', count: 2 };
    const { roots, childrenByParent } = buildTree([PARENT, mixedChild]);
    const counts = computeCounts(roots, childrenByParent);
    assert.equal(counts.get('amecro'), 5); // parent only
    assert.equal(counts.get('norcar'), 2); // child only
  });
});

// -- countsInRange (full pipeline) --

describe('countsInRange', () => {
  it('returns positive counts for in-range records', () => {
    const counts = countsInRange([PARENT, ADJUSTMENT], IN_RANGE);
    assert.equal(counts.get('amecro'), 2);
  });

  it('drops taxa with non-positive totals', () => {
    const zero = { ...ADJUSTMENT, count: -5 }; // wipes out the parent's 5
    const counts = countsInRange([PARENT, zero], IN_RANGE);
    assert.equal(counts.has('amecro'), false);
  });

  it('returns empty map for out-of-range data', () => {
    const counts = countsInRange([PARENT, ADJUSTMENT], OUT_RANGE);
    assert.equal(counts.size, 0);
  });

  it('excludes orphans from totals', () => {
    const counts = countsInRange([PARENT, ADJUSTMENT, ORPHAN], IN_RANGE);
    assert.equal(counts.has('norcar'), false);
    assert.equal(counts.get('amecro'), 2);
  });

  it('in-range parent contributes full subtree even when child dates are outside range', () => {
    // Child date is in August but parent is in July (in range) → child still counts
    const futureChild = { ...ADJUSTMENT, begin: '2026-08-01T00:00:00Z', end: '2026-08-01T00:00:00Z' };
    const counts = countsInRange([PARENT, futureChild], IN_RANGE);
    assert.equal(counts.get('amecro'), 2); // 5 + (-3)
  });

  it('swipe-delete pattern (adjustment zeroes parent) hides species from summary', () => {
    const deleteAdj = { ...ADJUSTMENT, count: -5 }; // exactly cancels parent count of 5
    const counts = countsInRange([PARENT, deleteAdj], IN_RANGE);
    assert.equal(counts.has('amecro'), false);
  });
});
