# Species List Sorting — Current Behavior

## Overview

The main species list in BirdCount is sorted so that the **most contextually relevant species appear at the bottom** of the scrollable list. The list's scroll anchor is always the bottom, meaning the last items in the sorted array are visually foregrounded (immediately visible without scrolling). The intent is that species likely to be tapped next appear closest to the interaction controls.

**Primary code:** `TaxonomyStore.search(_:minCommonness:maxCommonness:dateRange:)` — `BirdCount/Stores/TaxonomyStore.swift:114`

---

## Step 1: Filtering

Filtering runs in two phases.

### Phase 1 — Fast path (abbreviation prefix + commonness)
Each taxon passes if:
1. Its `commonness` value is within `[minCommonness, maxCommonness]` (only enforced when a checklist is selected; `minCommonness`/`maxCommonness` come from `SettingsStore`)
2. Any of its abbreviations starts with the search query (case-insensitive prefix match)
   - Abbreviations are generated at load time from initials of each word in the common name and scientific name

If the query is empty, step 2 of the abbreviation check is skipped and all commonness-passing taxa are included.

### Phase 2 — Fallback full-text search
If Phase 1 returns an empty array **and** the query is non-empty, a second pass runs the same commonness filter but adds a full-text `contains` match against `commonName` and `scientificName`.

### Commonness values
| Value | Meaning |
|-------|---------|
| `nil` | Not in active checklist / unknown |
| `0`   | Rare |
| `1`   | Uncommon |
| `2`   | Fairly common |
| `3`   | Common |

`nil` taxa pass any commonness filter (they are unaffected by the slider).

---

## Step 2: Sorting

After filtering, `compareTaxa` sorts taxa into two buckets. Within the sorted array, lower indices are at the **top** of the visual list (scrolled away) and higher indices are at the **bottom** (immediately visible).

### Bucket A — "Recent" species (bottom of list)
A taxon is "recent" if it has at least one observation record with `totalCount > 0` whose time range overlaps the **active date range** (`DateRangeStore.dateRange`).

Recent species are sorted **older → newer** by the latest `end` date of their in-range observation records. The most recently observed species ends up at the very bottom.

### Bucket B — "Non-recent" species (top of list)
All taxa not observed in the active date range fall into this bucket. They are sorted by three tie-breaking criteria in order:

1. **Commonness ascending** — rarest (`0`) first, most common (`3`) last; `nil` sorts last (treated as `Int.max`)
2. **Taxonomy order ascending** — eBird taxonomic sequence (`Taxon.order`)
3. **Common name alphabetically** — A → Z

The net effect: among non-recent species, the **most common** ones in the active checklist appear closest to the bottom of bucket B, just above the recent species.

### Sort summary (top → bottom of visual list)

```
┌─────────────────────────────────────────┐  ← scroll up to see
│  Non-recent, nil commonness             │
│  Non-recent, commonness 0 (rare)        │
│  Non-recent, commonness 1               │
│  Non-recent, commonness 2               │
│  Non-recent, commonness 3 (common)      │
├─────────────────────────────────────────┤
│  Recent: observed least recently        │
│  Recent: ...                            │
│  Recent: observed most recently         │  ← always visible at bottom
└─────────────────────────────────────────┘
```

---

## Data Sources

| Data | Source |
|------|--------|
| Taxon commonness | `TaxonomyStore.checklistSpeciesCommonness` loaded from the selected checklist JSON file |
| Active date range | `DateRangeStore.dateRange` (presets: Last Hour, Today, Last 7 Days, All, Custom) |
| In-range observations | `ObservationStoreProxy.shared.observationsInRange(effectiveDateRange)` |
| Latest in-range date per taxon | Computed from `obs.end` across in-range records |
| Global last-observed dates | `ObservationStoreProxy.shared.lastDatesSnapshot()` — computed but **currently unused** in sort logic |

> **Note:** `globalLastDates` is fetched during each `search()` call and passed to `compareTaxa`, but `compareTaxa` never reads it. It has no effect on the current sort order.

---

## Date Range Behavior

If no `dateRange` argument is provided to `search()`, `DateRange.defaultRange()` is used as a fallback (today only, midnight→23:59:59). In practice `HomeView` always passes `dateRangeStore.dateRange`.

### Date range presets (`DateRangePreset`)
| Preset | Range |
|--------|-------|
| `.lastHour` | now−1h → now |
| `.today` | start of today → start of tomorrow |
| `.last7Days` | now−7d → now |
| `.all` | `.distantPast` → `.distantFuture` |
| `.custom` | user-defined |

When `.all` is selected, **all** species with any observation become "recent" and sort into bucket A. The non-recent bucket becomes everything never observed.

---

## Checklist Integration

When `SettingsStore.selectedChecklistId` is non-nil:
- The corresponding JSON checklist file is loaded into `TaxonomyStore.checklistSpeciesCommonness` (keyed by taxon ID)
- The `minCommonness`/`maxCommonness` filter range is applied during search
- Species absent from the checklist have `commonness = nil` and pass the filter unconditionally

When no checklist is selected, the `minCommonness`/`maxCommonness` parameters passed to `search()` are `nil`, so no commonness filtering is applied (all taxa pass). Commonness-based sort ordering still functions based on whatever `commonness` values taxa carry.

---

## UI Integration

- **`HomeView`** computes `filtered` by calling `taxonomy.search(...)` reactively
- **`SpeciesListView`** always scrolls to the bottom: on appear, on taxa change, and when `scrollToBottomSignal` fires
- After recording an observation, `HomeView` clears the filter text, fires `scrollToBottomSignal`, and sets `recentlyUpdatedSpeciesId` (triggering a pulse animation on the newly-recent species row)

---

## Noted Issues / Gaps

1. **`globalLastDates` is computed but never used.** It's fetched in `search()` and passed to `compareTaxa`, but `compareTaxa` ignores it. This was likely intended to break ties among non-recent species by recency of past observation but was never wired up.

2. **No recency signal within bucket B.** Non-recent species that were observed yesterday (just outside the date range) sort identically to species never observed. The unused `globalLastDates` snapshot would enable this tie-break.

3. **`nil` commonness sorts last in bucket B**, not first — meaning species absent from the checklist appear between common checklist species and the recent bucket, rather than grouped at the top away from the focus area. Whether this is intentional is unclear.

4. **Observations with `totalCount == 0` are excluded** from the recent set (`filter { $0.totalCount > 0 }`), so a record that exists but has a zero count does not pull a species into bucket A.

---

## Proposed Feature: Proximate Observations (Bucket C)

### Motivation

When the active date range is narrow (e.g., "Last Hour" or "Today"), species the user has seen recently — say, earlier this week at the same location — fall into the undifferentiated bucket B and are buried under hundreds of unobserved taxa sorted only by checklist commonness. The user has clear contextual evidence these species are likely, but the sort order ignores it.

The proposal introduces **bucket C ("proximate")** between the existing bucket B (non-recent) and bucket A (in-range), capturing species observed within a rolling time window, near the same location, and weighted by how frequently they have appeared.

### Key Definitions

#### Lookback window
The proximate window spans the **14 days ending at `dateRange.end`** (the end of the active date range, not wall-clock now). This means the window shifts as the user changes the date range filter, keeping bucket C contextually aligned with whatever session the user is examining.

```
dateRange.end − 14 days  ──────────────────────  dateRange.end
                                  [proximate window]
```

#### Proximate location
The reference point for distance comparison is **not** the device GPS. Instead, it is the `ObservationLocation` of the **most recent observation record** (by `end` date) within the proximate window that has a valid location. Call this `proximateAnchor`.

This design:
- Requires no location permission at sort time
- Automatically reflects where the user was birding most recently
- Degrades cleanly: if no records in the window have a location, `proximateAnchor` is nil and bucket C is empty

#### Proximate record
An `ObservationRecord` qualifies as proximate if **all** of the following hold:
1. `record.end` is within the proximate window (`dateRange.end − 14 days ≤ record.end ≤ dateRange.end`)
2. `record.totalCount > 0`
3. `record.location` is non-nil and within **32 km (≈ 20 miles)** of `proximateAnchor`

Records without a stored location are **not proximate** — they cannot satisfy criterion 3.

#### Proximate taxon
A taxon is proximate if it has at least one proximate record AND is not already in bucket A.

### Bucket C Sort Order: Frequency Weight

Within bucket C, taxa are sorted by **proximate frequency** — the count of qualifying proximate records for that taxon (`record.totalCount > 0`, within window, within distance). Taxa with higher frequency sort closer to the bottom (more prominent, nearer to bucket A).

**Tie-break:** taxa with equal frequency sort by most recent qualifying `end` date, older → newer, so the most recently seen ties appear lower.

The intuition: a species recorded five times across three days nearby is a much stronger signal than one recorded once. Frequency better captures "this is reliably here" than recency alone.

### Updated Bucket Hierarchy (top → bottom)

```
┌─────────────────────────────────────────┐  ← scroll up to see
│  BUCKET B: Non-recent, non-proximate    │
│    nil commonness (not in checklist)    │
│    commonness 0 (rare)                  │
│    commonness 1                         │
│    commonness 2                         │
│    commonness 3 (common)                │
├─────────────────────────────────────────┤
│  BUCKET C: Proximate (outside range)    │
│    least frequent in window             │
│    ...                                  │
│    most frequent in window              │
├─────────────────────────────────────────┤
│  BUCKET A: In active date range         │
│    observed least recently in range     │
│    ...                                  │
│    observed most recently in range      │  ← always visible at bottom
└─────────────────────────────────────────┘
```

### Degradation Behavior

| Condition | Behavior |
|-----------|----------|
| Records with locations exist in window | Full time + distance filter; `proximateAnchor` = most recent located record |
| No records with locations in window | `proximateAnchor` = nil → bucket C is empty |
| Active date range is `.all` | Bucket C is empty (all observed taxa are already in bucket A) |
| Record has no `location` | That record is ineligible; taxon can still qualify via other records that do have a location |

### Impact on Existing Code

#### `ObservationStore` / `ObservationStoreProxy`
Add a snapshot method:
```swift
// Returns all records (flattened from top-level + children) where
// record.end is within [cutoff, rangeEnd] and totalCount > 0
func observationsInWindow(from cutoff: Date, to rangeEnd: Date) -> [ObservationRecord]
```
This is purely a time filter. Location filtering and anchor derivation happen in `TaxonomyStore` where the full sort context is available.

#### `TaxonomyStore.search()`
Before sorting, compute the proximate context:
```
1. cutoff = dateRange.end − 14 days
2. windowRecords = ObservationStoreProxy.shared.observationsInWindow(from: cutoff, to: dateRange.end)
3. proximateAnchor = windowRecords
       .filter { $0.location != nil }
       .max(by: { $0.end < $1.end })?.location
4. If proximateAnchor == nil → proximateTaxonIds = [], proximateFrequency = [:]
5. Else:
     qualifying = windowRecords.filter {
         $0.location != nil &&
         $0.location!.distance(to: proximateAnchor) <= 32_187 &&
         !recentTaxonIds.contains($0.taxonId)
     }
     proximateTaxonIds = Set(qualifying.map { $0.taxonId })
     proximateFrequency = Dictionary grouping count of qualifying records per taxonId
```
Remove the now-unused `globalLastDates` computation.

#### `compareTaxa(_:_:...)`
New signature passes `proximateTaxonIds` and `proximateFrequency`:
```
if ra != rb       →  non-recent before recent (unchanged)
if ra && rb       →  sort by lastDatesInRange (unchanged)
if pa != pb       →  non-proximate before proximate (new)
if pa && pb       →  sort by proximateFrequency ascending,
                      tie-break by lastProximateDate ascending (new)
else              →  applyStableTieBreakers (unchanged)
```
Where `pa`/`pb` = `proximateTaxonIds.contains(a.id)` / `...contains(b.id)`.

### Resolved Design Questions

1. **Records without location**: not proximate. Distance criterion requires a valid `location`; there is no fallback.
2. **Time anchor**: end of active date range. Proximate location = location of most recent located record in the window.
3. **Sort within bucket C**: by frequency (count of qualifying records), ascending so highest frequency is at the bottom; tie-break by most recent qualifying `end` date.
4. **Empty window**: bucket C is naturally empty; no special handling needed.

