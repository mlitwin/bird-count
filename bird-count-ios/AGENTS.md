# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) or copilot when working with code in this repository.

## Build Commands

```bash
make generate      # Regenerate Xcode project from project.yml (required after adding files)
make build-test    # Quick compile check - run this after edits
make test          # Run all tests (core + app)
make test-core     # Fast macOS tests for pure Swift logic (no simulator)
make test-app      # iOS Simulator tests
make clean         # Clean build artifacts
```

**Requirements:** Xcode 15+, Swift 5.9+, XcodeGen (`brew install xcodegen`)

## Quick Rules

- Always run `make build-test` after edits to verify compilation
- Never edit `.xcodeproj` or `Info.plist` by hand — edit `project.yml` and run `make generate`
- Never inline user-facing strings — use localization workflow (see below)
- Use SwiftUI and the Store pattern (`@Observable` stores via `.environment`)
- Keep views thin — compute derived values in stores, not views
- Heavy IO/decoding off main thread; UI updates on main

## Architecture

SwiftUI app using **MVVM with Observable Stores**. See `Architecture.md` for full details.

**Key Stores:**
- `ObservationStore`: Bird sighting records, counts, persistence (UserDefaults + JSON with ISO8601 dates); also cloud-sync state (dirty ids, cursor, LWW merge)
- `TaxonomyStore`: Species taxonomy from bundled JSON, search with abbreviation mode
- `SettingsStore`: User preferences (UserDefaults with "Settings_" prefix)
- `DateRangeStore`: Active date range (presets or custom)

**Cloud services** (`Cloud/`, app target only — NOT in BirdCountCore):
- `CloudAuthService`: Sign in with Apple via Cognito hosted UI (PKCE); tokens in Keychain
- `CloudSyncService`: manual + debounced auto sync against the backend
- `CloudConfig`: loaded from `Resources/cloud-config.json` (Debug→dev, Release→prod)

**Data Flow:** User action → store mutation → persistence → cache rebuild → SwiftUI re-render

**Range Filtering:** A record is "in range" iff `record.end >= start && record.begin <= end`

**Ledger invariants (do not break):**
- Records are immutable ledger entries; count changes are appended *adjustment
  children* (negative counts allowed). Never mutate counts in place; never
  add delete/tombstone concepts. The one allowed mutation is the location
  backfill (`updateWithLocation`), which bumps `updatedAt`.
- Every create/mutation must mark the record dirty (existing store APIs do
  this); imports merge via `store.mergeDTOs` (put-if-absent + LWW on
  `updatedAt`) — never mint new UUIDs for transferred records.
- Wire format is owned by `../bird-count-schema/`; `SchemaConformanceTests`
  (TestsCore) is the drift gate. If you change `ObservationRecordDTO`
  coding, the schema + fixtures + backend must change in the same commit.
- Full protocol details: `../docs/sync-architecture.md`

## Localization

All user-facing strings must be localized:

1. Add key/value to `BirdCount/Resources/Localizations/en.lproj/Localizable.strings`
2. Add constant in `BirdCount/Localization/Strings.swift`
3. Use in code: `Text(Strings.General.cancel.string)` or `.localizedStringKey`
4. For interpolation: `String(format: Strings.*.string, ...)`

## Testing

- Tests use Swift's `Testing` package with `#expect` patterns
- `TestsCore/` — fast macOS tests for pure Swift logic (no simulator)
- `Tests/` — iOS tests requiring simulator
- Add minimal tests for public behaviors: one happy path + one edge case
- Tests must be deterministic and fast

## Adding Dependencies

Do not add external dependencies without:
1. Updating `Package.swift`
2. Documenting the reason in the PR
3. Running `make build-test` and validating tests pass

## Before Committing

- [ ] `make build-test` passes
- [ ] Relevant tests pass (`make test-core` for models/stores)
- [ ] If files added: `project.yml` updated and `make generate` run
- [ ] Changes to persistence include migration plan if breaking

## When to Call a Human

- Changes to persisted data schema/migration
- Dependencies with security or licensing implications
- Architectural decisions (e.g., store redesign)

## Key Files

| File | Purpose |
|------|---------|
| `project.yml` | XcodeGen project definition (source of truth) |
| `BirdCount/Localization/Strings.swift` | Localization constants |
| `BirdCount/Stores/` | Store implementations |
| `Architecture.md` | Detailed architecture documentation |
| `Makefile` | Build/test automation |

## Directory Structure

```
BirdCount/
├── Models/          # Data models (ObservationRecord, DTO, Taxon, DateRange, import/export)
├── Stores/          # Observable state containers (+ cloud sync state in ObservationStore)
├── Views/           # SwiftUI views by feature (Home/, Summary/, Log/, Settings/)
├── Sync/            # P2P sync (Bonjour/TCP peer sessions)
├── Cloud/           # Cloud sync (Cognito/SIWA auth, API client, sync service, config)
├── Localization/    # Strings.swift constants
└── Resources/       # Bundled JSON (taxonomy, checklists, cloud-config), assets

Tests/               # iOS unit tests (simulator, app-hosted)
TestsCore/           # Cross-platform core tests (fast, no simulator);
                     #   includes SchemaConformanceTests against ../bird-count-schema fixtures
```

Note: `BirdCountCore` (macOS framework) compiles only `Models/` + `Stores/` —
anything placed there must stay platform-neutral (no UIKit/AuthenticationServices).
The store↔cloud decoupling is via `ObservationStore.didMarkDirtyNotification`.
