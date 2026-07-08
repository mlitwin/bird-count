// ledger.js — DTO tree construction and range-filtered count aggregation.
// Mirrors iOS ObservationStoreCache.countsInRange semantics exactly:
//   - range filter applies only to top-level records
//   - an in-range parent contributes its entire subtree (including out-of-range children)
//   - orphaned DTOs (parentId present but parent absent) are excluded from totals

/**
 * Build a tree index from a flat DTO array.
 *
 * @param {Object[]} dtos
 * @returns {{ roots: Object[], childrenByParent: Map<string, Object[]> }}
 *   roots            — DTOs with no parentId
 *   childrenByParent — map from parentId → child DTOs (orphans excluded)
 */
export function buildTree(dtos) {
  const ids = new Set(dtos.map(d => d.id));
  const roots = [];
  const childrenByParent = new Map();

  for (const dto of dtos) {
    if (!dto.parentId) {
      roots.push(dto);
    } else if (ids.has(dto.parentId)) {
      let siblings = childrenByParent.get(dto.parentId);
      if (!siblings) { siblings = []; childrenByParent.set(dto.parentId, siblings); }
      siblings.push(dto);
    }
    // orphan: parentId set but parent absent → silently excluded
  }

  return { roots, childrenByParent };
}

/**
 * Filter top-level records by date range.
 * Predicate: record.end >= range.begin && record.begin <= range.end (ISO strings).
 * Passing roots carry their entire subtree — do not re-filter children.
 *
 * @param {Object[]} roots
 * @param {{ begin: string, end: string }} range
 * @returns {Object[]}
 */
export function filterInRange(roots, range) {
  const begin = new Date(range.begin).getTime();
  const end = new Date(range.end).getTime();
  return roots.filter(r =>
    new Date(r.end).getTime() >= begin && new Date(r.begin).getTime() <= end
  );
}

/**
 * Compute per-taxonId counts from in-range roots and their subtrees.
 * Each record contributes its own count to its own taxonId (mirrors iOS processRecord).
 *
 * @param {Object[]} inRangeRoots
 * @param {Map<string, Object[]>} childrenByParent
 * @returns {Map<string, number>} — may include zero or negative entries; caller filters
 */
export function computeCounts(inRangeRoots, childrenByParent) {
  const counts = new Map();

  function process(dto) {
    counts.set(dto.taxonId, (counts.get(dto.taxonId) ?? 0) + dto.count);
    for (const child of (childrenByParent.get(dto.id) ?? [])) {
      process(child);
    }
  }

  for (const root of inRangeRoots) {
    process(root);
  }

  return counts;
}

/**
 * Convenience: build tree, apply range filter, compute counts, drop non-positive entries.
 * This is the main entry point for the summary view.
 *
 * @param {Object[]} dtos - flat observation DTOs from the API
 * @param {{ begin: string, end: string }} range
 * @returns {Map<string, number>} taxonId → positive count only
 */
export function countsInRange(dtos, range) {
  const { roots, childrenByParent } = buildTree(dtos);
  const inRange = filterInRange(roots, range);
  const counts = computeCounts(inRange, childrenByParent);

  // iOS hides species with totalCount <= 0 in the summary view
  for (const [id, n] of counts) {
    if (n <= 0) counts.delete(id);
  }

  return counts;
}
