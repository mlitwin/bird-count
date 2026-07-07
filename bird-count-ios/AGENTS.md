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
- `ObservationStore`: Bird sighting records, counts, persistence (UserDefaults + JSON with ISO8601 dates)
- `TaxonomyStore`: Species taxonomy from bundled JSON, search with abbreviation mode
- `SettingsStore`: User preferences (UserDefaults with "Settings_" prefix)
- `DateRangeStore`: Active date range (presets or custom)

**Data Flow:** User action → store mutation → persistence → cache rebuild → SwiftUI re-render

**Range Filtering:** A record is "in range" iff `record.end >= start && record.begin <= end`

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
├── Models/          # Data models (ObservationRecord, Taxon, DateRange)
├── Stores/          # Observable state containers
├── Views/           # SwiftUI views by feature (Home/, Summary/, Log/, Settings/)
├── Sync/            # Network sync (Bonjour-based device sync)
├── Localization/    # Strings.swift constants
└── Resources/       # Bundled JSON (taxonomy, checklists), assets

Tests/               # iOS unit tests
TestsCore/           # Cross-platform core tests (fast, no simulator)
```
