# bird-count-schema

Single source of truth for the observation wire format, shared by the backend
(`bird-count-backend/api`), the iOS app (`bird-count-ios`), and the web viewer
(`bird-count-web`).

- `schemas/` — JSON Schema (draft 2020-12) for the observation ledger entry,
  location, `/v1/sync` request/response, and the P2P payload. The data model is
  an append-only ledger: no deletes, no tombstones — an adjustment child with a
  negative count zeroes out its parent.
- `fixtures/valid/`, `fixtures/invalid/` — golden fixtures. The backend's ajv
  validation, the iOS `SchemaConformanceTests`, and the web viewer's
  response-shape tests all consume these, so schema drift on any side fails
  that side's tests in the same commit.
- `fixtures/derived/summary-cases.json` — golden expected `/v1/summary`
  aggregations over the valid fixture graph. The backend query tests and the
  iOS conformance tests both check these, locking ledger semantics between
  the server and the offline-first iOS implementation.
- `VERSION` — schema version stamp; matches the wire `schemaVersion` field.

## Usage

```sh
npm install
npm run validate   # every valid fixture passes, every invalid fixture fails
npm run generate   # emit bird-count-backend/api/src/generated/types.ts
```

Generated types are checked in; CI regenerates and fails on diff.
