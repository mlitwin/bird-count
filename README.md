# Bird Count

Monorepo for the Bird Count app and its cloud backend.

| Directory | Status | Summary |
|---|---|---|
| `bird-count-ios` | **Active / live app** | Current iOS app (SwiftUI, offline-first, P2P + cloud sync). The main product codebase. |
| `bird-count-backend` | **Active** | Cloud sync backend: Cognito + Sign in with Apple, API Gateway + Lambda, DynamoDB ledger; Terraform, deployed via GitHub Actions (main → dev, vX.Y.Z tag → prod). |
| `bird-count-schema` | **Active** | Shared wire-format JSON Schemas + golden fixtures; single source of truth consumed by both the backend (codegen + ajv) and iOS (conformance tests). |
| `bird-count` | **Legacy / exploratory** | Older React-era project with additional backend/frontend experiments and taxonomy tooling/data. Reference only; prune once no longer needed. |

## Taxonomy note

`bird-count` includes taxonomy datasets and processing scripts under `taxonomy/`.  
`bird-count-ios` includes the app-consumed taxonomy resource at `BirdCount/Resources/ios_taxonomy_min.json` and a generation script at `BirdCount/Scripts/generate_ios_taxonomy.mjs`.

## Traced lineage: `US-ME` -> `checklist-US-ME.json`

1. Raw Maine data source is eBird recent observations JSON (`US-ME` region), documented in `bird-count/taxonomy/eBird/README.md`:
   `curl ... /v2/data/obs/US-ME/recent > US-ME.json`.
2. In this workspace, `bird-count/taxonomy/US-ME.json` is byte-identical to `bird-count/taxonomy/eBird/US-ME.json` and has raw eBird observation shape (array of records with `speciesCode`, `obsDt`, `lat/lng`, etc.).
3. Historical generation step is in `bird-count` commit `53e516a` ("Maine"):
   - `taxonomy/ebird.js` was configured to read `./eBird/US-ME.json`
   - It produced `./checklist-US-ME.json` as a commonness map over the eBird taxonomy (`0/1/2/3` levels)
   - `taxonomy/Makefile` copied `checklist*.json` into `frontend/src/data/`
4. `bird-count-ios/data/checklist-US-ME.json` is byte-identical to `bird-count/frontend/src/data/checklist-US-ME.json`, and entered iOS in initial commit `0a8b4bf`.

Practical summary: iOS `checklist-US-ME.json` comes from the older `bird-count` taxonomy pipeline, ultimately seeded by eBird US-ME recent-observation data and transformed by the historical `taxonomy/ebird.js` script variant used in the "Maine" commit.
