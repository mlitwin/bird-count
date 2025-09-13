# Copilot Instructions for this Swift iOS App

These guidelines help AI coding assistants generate changes that fit this project’s structure, tools, and conventions.

## General Rules

- Do: After a change, run 'make build-test' to ensure everything works as expected. 

## Scope and targets
- Platform: iOS (target 18.5+), Swift 5.x, SwiftUI-first.
- State: Use Swift Observation (@Observable) stores injected via `.environment`.
- UI: SwiftUI views; avoid UIKit unless strictly necessary.

## Project structure and tools
- Project is generated with XcodeGen (`project.yml`).
  - Don’t hand-edit `.xcodeproj`; update `project.yml` and run the generator.
- Automation via Fastlane (bundled): generate/build/test/archive.
- Tests live in `Tests/` and use the `Testing` package with `#expect`.

## Architecture highlights
- Stores (in `Stores/`):
  - `TaxonomyStore`: loads taxonomy JSON, optional checklist overlays, search/sort; avoid blocking main thread for IO/decoding.
  - `ObservationStore`: immutable `ObservationRecord`s, derived caches in `ObservationStoreCache`, persistence in `UserDefaults` with ISO8601 dates.
  - `SettingsStore`: user preferences (checklist/commonness bounds, etc.).
- Models: `Taxon`, `ObservationRecord`.
- Views: SwiftUI components under `Views/` (Home, Summary, Components, Settings).

## Data and sorting rules (Home species list)
- Order results:
  1) Species seen within last 24h at the bottom (oldest→newest within this bucket; newest is last).
  2) Others: by commonness ascending (rare→common), tie-break by last observed older→newer, then taxonomy `order`, then `commonName`.
- Range overlap when filtering observations: `record.end >= start && record.begin <= end`.

## SwiftUI conventions
- Prefer stateless, composable views with explicit inputs.
- Use `defaultScrollAnchor(.bottom)` and/or `ScrollViewReader` for bottom-anchored lists.
- Use iOS 17+ `onChange` signatures (`onChange(of:) { old, new in … }`).
- Keep overlays non-blocking: measure intrinsic sizes with `GeometryReader` + `PreferenceKey` as needed.

## Coding style
- Keep functions small and pure; move logic out of views into stores/helpers.
- Use `private`/`fileprivate` appropriately.
- Avoid force unwraps; use safe fallbacks and clear errors for UI.

## Persistence
- `ObservationStore` uses `UserDefaults` with JSON encoder/decoder (ISO8601 dates). Keep schemas backward-compatible.

## Performance
- Large JSON: memory-mapped Data and minimal decoding.
- Maintain id→index maps for fast mutation (e.g., taxonomy incremental updates).

## Testing
- Add minimal unit tests for public behaviors: one happy path + an edge case.
- Example:
  ```swift
  @Test func example() throws { #expect(1 + 1 == 2) }
  ```

## Do/Don’t
- Do: Update `project.yml` for file changes; regenerate the project.
- Do: Keep UI updates on main; heavy IO/decoding off main.
- Do: Respect the sorting and range rules above.
- Don’t: Introduce deps without updating manifests/docs.
- Don’t: Hardcode resource paths; use `Bundle.main.url(forResource:withExtension:)`.

## Handy references
- Sorting: `compareTaxa(_:_:)` in `TaxonomyStore` encapsulates species ordering.
- Derived cache: `ObservationStoreCache` exposes `counts` and `lastObservedAt`.

If unsure, prefer small, incremental changes with tests and docs updates.
