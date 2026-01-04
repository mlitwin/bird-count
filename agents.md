# Copilot / Agent Guidelines for this Swift iOS App

Purpose
- Short, actionable rules for automated assistants and contributors working on this repository.
- Keep changes small, testable, and aligned with repo conventions (XcodeGen, SwiftUI-first, Stores, Localization).

Quick rules (TL;DR)
- Always run: make build-test after edits to verify compilation before committing.
- Do not edit `.xcodeproj` or `Info.plist` by hand. Edit `project.yml` and re-generate the project.
- Use SwiftUI and the project's Store pattern (Observable stores injected via `.environment`) — avoid UIKit unless essential.
- Never inline user-facing strings; add strings to `Localizable.strings` and the `Strings.swift` constants, then use `Strings.*` in code.
- Heavy IO and decoding should run off the main thread; UI updates must be on main.
- Don't add dependencies without updating manifests (top-level `Package.swift`) and documenting why.

Platform / toolchain
- Target: iOS 18.5+; Swift 5.x; SwiftUI-first.
- Project generator: XcodeGen using `project.yml`. Update `project.yml` for file or Info properties changes; do not hand-edit generated Xcode project files.
- Tests: unit tests live in `Tests/` (and `TestsCore/`). Use the repo's `Testing` package conventions.

Editing files
- Read the relevant files before editing (models, stores, views). Aim for minimal, focused changes.
- Follow existing file and naming conventions (private/fileprivate usage, small pure functions, move logic out of views into stores/helpers).
- If you add files, update `project.yml` and commit those changes. Then regenerate the Xcode project as part of the PR instructions (document regeneration steps in the PR).
- For build settings, Info.plist keys, or permission strings (camera/location), add them to `project.yml` under `info.properties` or the appropriate `project.yml` section.

Localization (must-follow)
- Never use hardcoded user-facing strings in UI code.
- Workflow to add a string:
  1. Add the key/value to `BirdCount/Resources/Localizations/en.lproj/Localizable.strings`.
  2. Add the corresponding constant in `BirdCount/Localization/Strings.swift`.
  3. Use the constant in code: `Text(Strings.General.cancel.string)` or `Text(Strings.General.cancel.localizedStringKey)` where appropriate.
  4. For format/interpolated strings, use `String(format: Strings.*.string, ...)`.
- Accessibility strings are localized the same way.
- Keep strings grouped by feature area (e.g., `General`, `Home`, `Species`, `Sync`).

Stores & state
- Use the repository's Store pattern (e.g., `TaxonomyStore`, `ObservationStore`, `SettingsStore`).
- Stores should be `@Observable` where appropriate and injected via `.environment`.
- Keep UI code thin: compute derived values in stores or helper types, not inside SwiftUI views.
- Persistence:
  - Observation persistence uses `UserDefaults` with JSON encoder/decoder and ISO8601 dates. Keep schemas backward-compatible.
  - When changing persistence schemas, include a migration plan in the PR.
- Caching: prefer explicit derived caches (e.g., `ObservationStoreCache`) for large or frequently computed values.

Performance & IO
- Large JSON: read with memory-mapped Data and decode off the main thread.
- Use id→index maps for fast mutations when applicable.
- Avoid blocking the main thread for file IO, decoding, or expensive computations. Use background tasks and publish results to main for UI updates.

Ordering & business logic
- Keep sorting and domain rules inside domain stores (e.g., `TaxonomyStore.compareTaxa(_:_:)`).
- Example ordering rules summary (from repo conventions):
  1. Species seen within last 24h appear in the bottom-of-list bucket (ordered oldest→newest within that bucket).
  2. Other taxa: by commonness ascending (rare→common), tie-break by last observed older→newer, then taxonomy order, then commonName.
- Range overlap for filtering: use `record.end >= start && record.begin <= end`.

Testing
- Add minimal unit tests for public behaviors: one happy path + one edge case.
- Tests must be deterministic and fast. Use the `Testing` package and `#expect` patterns.
- After changes, run:
  - `make build-test` (quick compile + test verification)
  - `make test` (or equivalent) for full test runs when appropriate.
- For UI behavior, prefer unit testing view models/stores over snapshotting UI unless absolutely necessary.

Adding dependencies
- Do not introduce external dependencies without:
  1. Updating top-level `Package.swift` (or other manifest in use).
  2. Recording reasons in the PR description and any security implications.
  3. Running `make build-test` and validating test coverage.
- New dependencies should be minimal and pinned. Prefer widely-adopted, well-maintained packages.

Resources & assets
- Do not hardcode resource file paths. Use `Bundle.main.url(forResource:withExtension:)`.
- When adding assets, add them to the asset catalog and update `project.yml` accordingly if needed.

Pull requests & code review
- Keep PRs small and focused.
- Required for PR:
  - Passing `make build-test`
  - Clear description of changes and any migrations
  - Tests added or updated for public behavior changes
  - Update docs or `agents.md` if agent/contributor rules changed
- If making changes to `project.yml`, include commands or steps to regenerate Xcode project in the PR description.

Quality gates (before merging)
- Build: make build-test — PASS
- Lint/Typecheck: no compile errors — PASS
- Unit tests: run and pass — PASS
- Small smoke test: manually verify the app launches and key flows (brief notes in PR) — PASS

Safety & security
- Never exfiltrate secrets or embed credentials.
- Do not make network calls during tests unless specifically mocked/stubbed.
- Document any changes to external endpoints, keys, or security-sensitive behavior.

When to call a human
- If a change touches migration of persisted data.
- If a proposed dependency has non-trivial security or licensing implications.
- If an architectural decision (e.g., store redesign) is required.

No-code-changes note (current request)
- The user explicitly requested: no source code edits in this round. This `agents.md` update is documentation-only. Do not change code until explicit approval is given.

Contacts & references
- `project.yml` — primary project configuration (XcodeGen)
- `BirdCount/Localization/Strings.swift` — canonical place for localization constants
- `BirdCount/Stores/` — store implementations & conventions
- `BirdCount/Resources/Localizations/` — localized `.strings` files
- `Makefile` — useful automation targets (e.g., `make build-test`)

Appendix: small examples (reference)
- Use localized strings:
  - `Text(Strings.General.cancel.string)` // correct
  - `Text("Cancel")` // wrong — avoid
- File IO:
  - `let url = Bundle.main.url(forResource: "taxa", withExtension: "json")`
  - `DispatchQueue.global(qos: .userInitiated).async { decode...; DispatchQueue.main.async { update store } }`

---

Changelog (what changed in this `agents.md`)
- Consolidated duplicated entries and removed repeated paragraphs.
- Reorganized content into concise sections: Quick rules, Platform/Toolchain, Editing files, Localization, Stores & State, Performance & IO, Testing, Dependencies, Resources & PRs.
- Added an explicit "No-code-changes note" to respect the user's instruction for this round.
- Added a small "Appendix" with quick actionable examples and a short Quality Gates checklist.

Assumptions made while drafting
1. The canonical localization constant file is `BirdCount/Localization/Strings.swift`.
2. The primary build/test command for fast verification is `make build-test`.
3. The project uses XcodeGen controlled by `project.yml` (do not modify `.xcodeproj` by hand).
4. Persistence for observations uses `UserDefaults` with JSON and ISO8601 dates per existing guidance.
5. Tests use the `Testing` package with `#expect`.

Reviewer checklist (next steps)
1. Review the proposed `agents.md` content for tone and any team-specific rules to add.
2. Confirm the localization file path and any other canonical file paths referenced.
3. If approved, I will keep this change and run verification (`make build-test`).
4. Optional: add a short PR template or link to existing PR checklist in the document.

Mapping: which parts of `Architecture.md` informed this update
- SwiftUI-first & Stores pattern: reinforced guidance to use `@Observable` stores and `.environment` injection.
- Sorting & domain rules: used Home species list ordering rules and added a short summary into Ordering & business logic.
- Persistence & performance: Architecture.md notes influenced the Persistence and Performance & IO sections.
- Code and UI conventions: Architecture.md's guidance about stateless views and moving logic to stores influenced the UI and Coding style phrasing.

If you'd like me to also commit this change and run `make build-test`, reply "commit and test" and I'll run it now.
