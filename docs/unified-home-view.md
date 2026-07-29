# Unified Home View — Design Proposal

## Motivation

The app currently has three tabs: **Home** (species entry), **Summary** (species + counts, taxonomic order), and **Log** (timestamped observation records). Summary and Log are largely read-only views of data that Home already shows. The proposal is to collapse all three into a single tab with a three-way view-mode toggle, eliminating the tab-switching mental overhead.

---

## Current Architecture

### Data model

`ObservationRecord` is a tree: each root record has a `taxonId`, `begin`/`end` dates, `count`, `location`, and `observer`. Adjustments are children with positive or negative `count` deltas. `totalCount` recursively sums the tree.

A "delete" in Log view is implemented as a child with `count = -totalCount` — a ledger entry, not a true removal.

### Views

| Tab | Sort | Scroll anchor | Key features |
|-----|------|---------------|--------------|
| Home | 3-bucket heuristic (recent observed → proximate → everything else) | Bottom | Tap → CountAdjustSheet, swipe-right quick-add, filter bar + on-screen keyboard |
| Summary | `taxon.order` (taxonomic) | Top | Species counts, totals banner, read-only |
| Log | Chronological (`record.begin`) | Bottom | Per-record rows, swipe-left adjust, swipe-right delete, tap → ObservationDetailsSheet |

---

## Proposed Unified Design

Remove Summary and Log tabs. Home gains a three-way view-mode toggle. From the user's perspective these are different views of the same data. In implementation, Recent and Taxonomic are nearly identical (species-aggregated rows, differ only by sort); Log is structurally different (individual record rows, not aggregated).

### Tab bar after unification

The bottom `TabView` is removed entirely — with only one logical tab it adds no value. The three-way view-mode toggle replaces it, pinned to the bottom of the screen in the same position the tab bar occupied.

Placing the toggle at the bottom has two ergonomic benefits:
1. Thumb-reachable on large phones.
2. The on-screen keyboard (filter bar) sits directly above it, keeping the keyboard-to-toggle distance short — the toggle nudges the keyboard up slightly rather than floating independently.

---

### 1. View-mode toggle

A segmented picker pinned to the bottom of the screen (replacing the tab bar). Persisted across app launches in `SettingsStore` or `UserDefaults`.

#### Recent (default)

Current Home behavior unchanged. Bottom-anchored scroll. 3-bucket heuristic sort. Tap → `CountAdjustSheet`. Swipe-right quick-add. Filter bar + on-screen keyboard. Scroll-to-bottom after adds.

#### Taxonomic

Species rows sorted by `taxon.order`. Top-anchored scroll (plain `ScrollView`, no bottom anchor). `HeaderSpacingView()` required before the list (currently absent in this branch because bottom-anchoring buries the top). Scroll-to-bottom signal suppressed after adds. Filter bar still works.

Both species modes show counts on every `SpeciesRow` (already implemented via `filteredCounts`). No totals banner — the species count in `ObservationsSelectorView` is sufficient.

**`SpeciesListView` change:** add `bottomAnchored: Bool = true`; when `false`, use a plain `ScrollView` instead of `BottomAnchoredScrollView`.

#### Log

Individual `ObservationRecord` rows, not aggregated by species. Chronological sort (`record.begin`, oldest first). Bottom-anchored scroll (matching current Log view). Rows rendered by `ObservationRecordView` (reused as-is). Filter bar filters by species name. Export button in the toolbar (currently in Log's navigation toolbar, stays there in Log mode).

Tap on a row → `ObservationDetailsSheet` for that record (current Log tap behavior).  
Swipe-left → adjust that record (`CountAdjustSheet` with `parentId`).  
Swipe-right → delete that record (zeroes via child, no extra confirmation needed — single record, clear scope).

---

### 2. Swipe-to-delete on SpeciesRow (Recent / Taxonomic modes)

In Log mode, delete targets a single `ObservationRecord`. In Recent/Taxonomic modes the unit is a species, which may span **multiple root records** from **multiple observers**, all filtered to the active date range.

**Interaction:** swipe-right on a `SpeciesRow` reveals a destructive Delete button. An alert confirms before executing:

> "Delete all observations of [Common Name]?"  
> **X observations · Y individuals · Z observers**  
> [Cancel] [Delete]

The observer list comes from `record.observers()` across all root records for that taxon within `dateRangeStore.dateRange`. The alert is always shown when count > 0.

**Implementation:** the delete operation iterates every root record for the taxon whose date falls within `dateRangeStore.dateRange`, appending a child with `count = -record.totalCount` to each. This preserves the ledger invariant and remains sync-safe.

**Delete scope:** date-range-scoped. Only records overlapping the active date filter are zeroed, matching what the user sees on screen.

---

### 3. Observation details via long press (Recent / Taxonomic modes)

Tap is already claimed by `CountAdjustSheet`. Long press on a `SpeciesRow` opens a **species-scoped detail bottom sheet** — consistent with the existing `CountAdjustSheet` overlay pattern.

The sheet shows:

- Species header (common name, scientific name, commonness badge)
- Totals for active date range: count, observer attribution
- **Timeline of root records** — each entry shows date, location, observer, individual count. Tapping a timeline entry deep-links to that record's full `ObservationDetailsSheet`.
- Summary stats: total individuals, adjustments applied

This gives users the audit trail currently available in Log view, but accessed in context without switching tabs.

In Log mode, long press is not needed — tap already opens `ObservationDetailsSheet` for the specific record.

**Bottom chrome layout:** the filter bar + on-screen keyboard stack already lives at the bottom of `HomeView`. The view-mode toggle is added as the lowest element of that same bottom chrome `VStack`, sitting just above the home indicator. In Log mode the on-screen keyboard is hidden (no species-entry use), so the toggle sits closer to the bottom edge. Switching to Recent or Taxonomic expands the keyboard above the toggle without moving the toggle itself.

---

### 4. Count adjust from Recent / Taxonomic modes — aggregated adjustment

`CountAdjustSheet` today requires a single `parentId` to compute the starting count and apply the delta as a child. In species-aggregated modes, the "current count" spans all root records.

**The aggregated adjustment:** `CountAdjustSheet` is opened without a `parentId` but with an injected `initialCount: Int` (from `filteredCounts[taxon.id] ?? 0`). On commit, the delta is `tempCount - initialCount`. If delta ≠ 0, a **new root record** is appended:

```
ObservationRecord(taxonId: taxon.id, count: delta, begin: now)
```

This is the "union of aggregated observations" — a new ledger entry representing the net adjustment across all existing records. Location is stamped as usual from `LocationManager`.

This approach is safe because:
- It doesn't require identifying which root record to mutate.
- It is compatible with sync (new record gets a fresh UUID, pushed as dirty).
- Attaching the delta as a child of one arbitrary root would create asymmetric history when multiple roots exist.

The existing `parentId` path remains unchanged for the Log-mode adjust (single record, precise delta parented to that record).

**`CountAdjustSheet` signature change:** when `parentId` is `nil`, initialise `tempCount` from `initialCount: Int` instead of looking up `parent.totalCount`. Callers in HomeView (species modes) pass `initialCount: filteredCounts[taxon.id] ?? 0`.

---

## File impact summary

| File | Change |
|------|--------|
| `Views/Home/HomeView.swift` | Add `ViewMode` enum (`.recent`, `.taxonomic`, `.log`) + persisted state; `sortedFiltered`; mode picker row; Log-mode list rendering; delete swipe + alert for species modes; long-press detail popup for species modes; pass `bottomAnchored` and `initialCount` |
| `Views/Components/SpeciesListView.swift` | Add `bottomAnchored: Bool = true` |
| `Views/Components/SpeciesRow.swift` | Add long-press gesture → callback; add swipe-right delete reveal |
| `Views/Components/CountAdjustSheet.swift` | Add `initialCount: Int?` init path for parentless aggregated adjust |
| `Views/Log/ObservationDetailsSheet.swift` | Extract species-scoped timeline sections for reuse in Home long-press sheet |
| `BirdCountApp.swift` | Remove `TabView` entirely; render `HomeView` directly as the window root |
| `Views/Summary/SummaryView.swift` | **Delete** |
| `Views/Log/ObservationLogView.swift` | **Delete** (Log mode rendered inline in HomeView) |
