# Native iOS App Plan: Bird Count

## 1. Goals & Scope
Replicate existing React web frontend functionality as a performant, offline‑first native iOS application while adopting iOS UI conventions. Provide: species selection & filtering, observation entry, summary (date range + stats + share/email), chronological log with swipe delete, settings/utilities. Defer cloud sync & auth (future).

MVP Success Criteria:
- Functional parity with web: Home (selector + filter + keyboard), Summary (range + export), Log (chronological with delete), Settings (basic).
- Offline operation; fast startup (< 1s on modern device after first taxonomy load).

## 2. Technology Choices
- Language/UI: Swift + SwiftUI (iOS 16+ minimum) – aligns with declarative pattern similar to React components.
- Architecture: MVVM with lightweight Stores (ObservableObject) for domain state.
- Persistence: Core Data for observations; taxonomy kept in memory from bundled JSON (simpler & immutable). Potential future: NSPersistentCloudKitContainer for sync.
- Concurrency: Structured concurrency (async/await) only where needed (e.g., loading taxonomy) – most operations synchronous & lightweight.
- Sharing: ShareLink / UIActivityViewController for summary export (supports Mail, Notes, etc.).

## 3. Domain Model Mapping
Web -> Native:
- Taxon { id: String, parentId: String?, commonName: String, scientificName: String, order: Int, rank: String }
- Observation { id: UUID, speciesId: String, startDate: Date, durationSeconds: Int, count: Int, parentId: UUID? }
- SpeciesSummary (computed) { species: Taxon, totalCount: Int, firstSeen: Date, lastSeen: Date, totalDuration: TimeInterval }
ObservationSet in web becomes computed grouping logic, not persisted.

## 4. Data & Persistence
- Bundle minimized taxonomy JSON (preprocessed subset of existing taxonomy.json).
- On launch load taxonomy into TaxonomyStore (dictionary by id + sorted array by order + search index tokens).
- Core Data Model: Observation entity only (fields above). Index startDate.
- Migration: Lightweight (additive only for MVP).

## 5. Application Flow
1. App start -> TaxonomyStore loads JSON -> ObservationStore initializes Core Data stack.
2. Root TabView shows Home, Summary, Log. Settings sheet via toolbar button.
3. Home: Filter species list; select species -> CountAdjustSheet -> save observation.
4. Summary: User adjusts start/end; view recomputes species summaries. Share exports text snapshot.
5. Log: Displays observations reverse chronological; swipe delete.

## 6. Screens & Components
A. Root
- AppTabView: TabView (Home, Summary, Log) with toolbar Settings button.

B. HomeView
- FilterBar: Shows current filter or “All species”; clear button.
- SpeciesList: LazyVStack of SpeciesRow (commonName + quick add button).
- OnScreenKeyboard: Custom grid (letters, backspace, space, clear) -> updates filter text.
- CountAdjustSheet: Modal sheet with stepper, +/- buttons, manual entry, cancel/save.

C. SummaryView
- DateRangeSelector: Start & End DatePickers + Today button + < / > day shift.
- StatsHeader: Species count, optional total individuals, formatted range string.
- SummaryList: SpeciesSummaryRow entries sorted by taxonomy order.
- Share button (toolbar) -> text export.

D. LogView
- ObservationList: List grouped by day (Section headers). Row shows time, species, count. Swipe to delete with confirmation or undo (optional).

E. SettingsView (Sheet)
- Data: Export all observations (JSON), Reset (destructive confirmation).
- About: Version/build number, license info.

## 7. View Models / Stores
- TaxonomyStore (ObservableObject): load(), search(filter:String)->[Taxon], taxonomyById, speciesSorted.
- ObservationStore (ObservableObject): create(speciesId,count), delete(observation), fetch(range) -> [Observation]; publisher for all recent observations; computed group(range)->[SpeciesSummary].
- HomeViewModel: @Published filterText, derived filteredSpecies (via TaxonomyStore.search).
- SummaryViewModel: @Published startDate, endDate; computed summaries & stats.
- LogViewModel: Provides date-grouped observations (ObservationStore subscription).

## 8. Algorithms & Logic
- Filtering: Lowercased contains on tokens (split names by whitespace/punctuation) – prefix optimization optional.
- Grouping: Fetch observations in range (predicate startDate BETWEEN); Dictionary grouping by speciesId -> aggregate counts & min/max date.
- Date navigation: Shift functions add days maintaining interval length.

## 9. Export / Share Format
Text (mirroring web):
"EEE M/d/yy h:mm a - EEE M/d/yy h:mm a | X species\n\n<count> <Common Name>\n..."
Use DateFormatter with locale-aware patterns.

## 10. Taxonomy Preprocessing Pipeline
Script (Node) reads existing taxonomy.json -> emits ios_taxonomy_min.json containing only required fields & species rank entries (skip synonyms if present). Sort by taxonomicOrder. Add build phase script in Xcode to regenerate when source changes.

## 11. Theming & UX
- System adaptive colors; support Dark Mode.
- Dynamic Type: Use relative text styles (title3, body, caption).
- Haptics: Light impact on add, notification success on batch save.
- Accessibility: Labels for buttons (+ button: “Increase count”, etc.).

## 12. Error Handling
- Persistence failures: Present alert; log via os_log.
- Corrupt taxonomy: Fallback to empty state + prompt to reinstall (rare).

## 13. Testing Strategy
Unit Tests:
- Taxonomy parsing
- Filter logic
- Summary grouping (counts, species uniqueness)
UI Tests:
- Add observation flow
- Filter reduces list
- Delete observation updates log & summaries
- Share sheet presence
Performance Tests:
- Taxonomy load (< 300ms)
- Grouping with large dataset (simulate 10k observations)

## 14. Project Structure
BirdCount/
  BirdCountApp.swift
  Resources/
    ios_taxonomy_min.json
  CoreData/
    BirdCount.xcdatamodeld
  Models/
    Taxon.swift
    Observation+CoreData.swift
    SpeciesSummary.swift
  Stores/
    TaxonomyStore.swift
    ObservationStore.swift
  ViewModels/
    HomeViewModel.swift
    SummaryViewModel.swift
    LogViewModel.swift
  Views/
    AppTabView.swift
    Home/
      HomeView.swift
      SpeciesRow.swift
      OnScreenKeyboard.swift
      CountAdjustSheet.swift
    Summary/
      SummaryView.swift
      DateRangeSelector.swift
      SpeciesSummaryRow.swift
    Log/
      LogView.swift
      ObservationRow.swift
    Settings/
      SettingsView.swift
  Utilities/
    Date+Formatters.swift
    SearchIndex.swift
  Scripts/
    generate_ios_taxonomy.mjs

## 15. Build & Tooling
- Swift Package Manager (no external deps MVP).
- Optional SwiftLint.
- Xcode build phase: node Scripts/generate_ios_taxonomy.mjs > Resources/ios_taxonomy_min.json

## 16. Implementation Phases
Phase 1: Project skeleton, taxonomy load, list display.
Phase 2: Filtering + on-screen keyboard.
Phase 3: Observation persistence (create/delete) & log view.
Phase 4: Summary calculations + date navigation + sharing.
Phase 5: Settings, export JSON, reset data.
Phase 6: Testing, accessibility, performance polish.
Phase 7: App Store prep (icons, screenshots, privacy).

## 17. Risks & Mitigations
- Large taxonomy memory: Trim JSON; lazy load if needed.
- Performance of grouping: Cache last computed interval; invalidate on mutation.
- Keyboard complexity: Start simple letters layout; future predictive search.
- Date/time localization: Use locale-aware formatters.

## 18. Future Enhancements (Post-MVP)
- iCloud/CloudKit sync
- Apple Watch quick add complication
- Siri Shortcuts (log observation voice)
- Location tagging & map
- Media attachments (photo/audio)
- Advanced fuzzy search
- Widgets (today’s counts)

## 19. Definition of Done (MVP)
- All core screens implemented & functional.
- Adding/deleting observations updates summary & log instantly.
- Export text correct & shareable.
- No crashes in test pass; memory stable.
- Accessibility labels & Dynamic Type verified.
- Startup taxonomy load time within target.

## 20. Open Questions
- Should duration be user-editable or fixed? (Currently auto; maintain parity.)
- Retain parent/child Observation structure? (If rarely used, omit parentId from UI but keep field.)
- Need local backup/export beyond share? (Settings JSON export covers.)

End of Plan.