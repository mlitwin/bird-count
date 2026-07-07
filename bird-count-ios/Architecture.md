# Architecture Overview

This document describes the iOS app’s architecture, key modules, and data flow. It’s intended for onboarding and as a reference during refactors.

## High-level structure

- SwiftUI app with a segmented top tab bar (Home, Summary, Log) and a global date range selector visible across screens.
- State is centralized in observable stores injected via environment:
	- TaxonomyStore: loads species taxonomy and optional region checklist overlays; search and filters.
	- ObservationStore: immutable event records with counts; derived per-species counts; persistence.
	- SettingsStore: user preferences (abbreviation search, theme, checklist + commonness filters, haptics).
- A reusable DateRangeSelectorView controls the active date range (relative presets or custom). Views compute an “effective range” and filter observations by interval overlap.

Key entry points:
- BirdCountApp.swift: bootstraps stores; hosts TopTabsRoot.
- TopTabsRoot (private View): segmented tabs, Settings sheet, and the global DateRangeSelectorView.

## Data model

ObservationRecord (Models/ObservationRecord.swift)
- id: UUID
- taxonId: String
- begin: Date
- end: Date (defaults to begin)
- count: Int (>= 0)

Notes
- Each record is an immutable event capturing a species (taxonId), a time interval [begin, end], and a count payload.
- begin == end represents an instantaneous sighting.
- All totals are derived by summing record.count.

Taxon (Models/Taxon.swift)
- id, commonName, scientificName, order, rank
- commonness: Int? (0 rare … 3 common)
- abbreviations: [String] generated from names for quick search.

## Stores

ObservationStore (Stores/ObservationStore.swift)
- observations: [ObservationRecord] (didSet persists and rebuilds derived state)
- counts: [taxonId: Int] rebuilt from observations
- recent: [Recent] with lastUpdated timestamps (MRU list)
- Mutations:
	- addObservation(taxonId, begin, end, count)
	- increment(id, by)
	- set(id, to) adjusts toward a target by removing/adjusting newest records first
	- reset(id), clearAll()
- Totals: totalIndividuals, totalSpeciesObserved
- Persistence: UserDefaults with JSONEncoder/Decoder using ISO8601 date strategy

TaxonomyStore (Stores/TaxonomyStore.swift)
- Loads bundled species file ios_taxonomy_min.json once; memory-mapped for performance.
- Optional region checklist overlays (e.g., checklist-US-CA-041.json, checklist-US-ME.json) apply commonness to matching species; cached in-memory.
- Async background decode for checklists; incremental updates to species.commonness via an id->index map.
- Search(text, minCommonness, maxCommonness) with optional abbreviation mode.

SettingsStore (Stores/SettingsStore.swift)
- User preferences persisted to UserDefaults under a namespaced key prefix.
- Checklist selection and commonness range with normalization and ordering enforcement.

## Global date range

DateRangeSelectorView (Views/Components/DateRangeSelectorView.swift)
- Presets: Last Hour, Today, 7 Days, All, Custom (sheet-driven).
- Summary text renders a compact one-line description of the active range.
- Relative presets are always resolved relative to “now”.

Effective range resolution in views
- For each screen, an effective (start, end) is computed as follows:
	- today: (startOfDay(now), now)
	- lastHour: (now-1h, now)
	- last7Days: (now-7d, now)
	- all: (.distantPast, now)
	- custom: (startDate, endDate)

Interval overlap predicate used consistently
- A record is “in range” iff record.end >= start && record.begin <= end.

## Views

BirdCountApp.swift
- Instantiates TaxonomyStore, ObservationStore, SettingsStore and injects them via .environment.
- Hosts TopTabsRoot (private View) with segmented tabs, Settings button, and the DateRangeSelectorView.

HomeView (Views/Home/HomeView.swift)
- Species list with optional checklist-based commonness filters and abbreviation search toggle.
- Range-aware counts per species: observations filtered by interval overlap with effective range, then sum record.count per taxonId.
- Tapping a species opens CountAdjustSheet as a custom intrinsic-height bottom overlay that sits above the bottom controls (FilterBar + OnScreenKeyboard). Overlay content measures its height and falls back to scrolling if needed.
- Navigation bar and background are hidden to eliminate top gaps.

SummaryView (Views/Summary/SummaryView.swift)
- Compact header row with title and Share button.
- Totals and “Species in Range” list are computed from observations filtered by effective range; sums record.count per species.
- Share uses ShareActivityView to export a text summary.
- Navigation bar and background are hidden.

ObservationLogView (Views/Summary/ObservationLogView.swift)
- Builds DisplayObservation array from observations filtered by effective range, sorts by begin.
- Renders rows via ObservationRecordView (resolves Taxon, date range, and ×N badge when count > 1).
- Export shares a TSV-like log with ISO8601 timestamps.
- Navigation bar and background are hidden; optional Close button when used as a sheet.

Components
- DateRangeSelectorView: global control; presets [← Today → All Custom]; Custom opens a sheet with DatePickers and enforces start ≤ end.
- CountAdjustSheet: compact count entry; step controls with integrated count display; commits one ObservationRecord with the selected count.
- ObservationRecordView: displays a record’s species, formatted date/time range, and ×N badge; tap to adjust counts via CountAdjustSheet.
- OnScreenKeyboard: virtual keyboard for Home filter text.
- ShareActivityView: UIActivityViewController wrapper.
	- CommonnessRangeView: extracted commonness range control used by SettingsView
	- SettingsView: preferences UI (abbreviation search, checklist selection + commonness bounds, haptics, theme, data reset).

## Persistence and resources

- ObservationStore persists observations as JSON in UserDefaults under key "ObservationRecords" with ISO8601 dates.
- SettingsStore persists each setting under a "Settings_"-prefixed key.
- Bundled resources: ios_taxonomy_min.json (taxonomy), checklist-*.json (per-region overlays). File ids in SettingsView must match bundled names.

## Performance notes

- Taxonomy JSON uses memory-mapped Data and background decode for checklists.
- Species id→index map accelerates incremental overlay updates.
- ObservationStore rebuilds derived counts on write; operations mutate a single array with O(n) behavior in worst-case decrements.
- Home overlay uses preference keys to measure intrinsic heights and avoids unnecessary layout work.

## Accessibility

- Rows and badges have accessibility labels (e.g., "Count N"), and ObservationRecordView combines child elements and provides a descriptive label with localized dates.
- Range summary and share/export strings use localized date/time formatting.

## Edge cases and invariants

- count is clamped to ≥ 0 when encoding/decoding and when adding records.
- set(_:to:) decreases from most recent records first; may trim or adjust a trailing record’s count.
- Range overlap logic includes boundary equality; begin may equal end.
- "All" range ends at now (not infinity) so relative totals update over time.
- Settings commonness bounds are normalized and ordered (0…3).

## Testing and previews

- Stores include lightweight preview helpers; key views provide #Preview configurations.
- Unit tests scaffold exists under Tests/BirdCountTests.swift.

## Build and run

- See README.md for requirements and run instructions. The app targets iOS 18.5+ and uses SwiftUI and the @Observable macro.

## Future improvements

- Batch export/import of observations (JSON or CSV).
- In-app analytics for session length and per-species rates.
- Merge adjacent records for the same species when times are within a small threshold.
- iCloud/Files persistence option in addition to UserDefaults.
- Snapshot tests for DateRangeSelectorView and range summaries.

