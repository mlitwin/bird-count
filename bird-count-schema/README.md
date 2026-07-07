# bird-count-schema

Single source of truth for the observation wire format, shared by the backend
(`bird-count-backend/api`) and the iOS app (`bird-count-ios`).

- `schemas/` — JSON Schema (draft 2020-12) for the observation ledger entry,
  location, `/v1/sync` request/response, and the P2P payload. The data model is
  an append-only ledger: no deletes, no tombstones — an adjustment child with a
  negative count zeroes out its parent.
- `fixtures/valid/`, `fixtures/invalid/` — golden fixtures. The backend's ajv
  validation and the iOS `SchemaConformanceTests` both consume these, so schema
  drift on either side fails that side's tests in the same commit.
- `VERSION` — schema version stamp; matches the wire `schemaVersion` field.

## Usage

```sh
npm install
npm run validate   # every valid fixture passes, every invalid fixture fails
npm run generate   # emit bird-count-backend/api/src/generated/types.ts
```

Generated types are checked in; CI regenerates and fails on diff.
