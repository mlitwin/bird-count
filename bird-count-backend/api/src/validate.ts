// Runtime request validation against the shared schemas (bundled at build time).
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";
import locationSchema from "../../../bird-count-schema/schemas/location.schema.json";
import observationSchema from "../../../bird-count-schema/schemas/observation.schema.json";
import syncSchema from "../../../bird-count-schema/schemas/sync.schema.json";
import type { SyncRequest } from "./generated/types.js";

const ajv = new Ajv2020({ allErrors: true });
addFormats(ajv);
ajv.addSchema(locationSchema);
ajv.addSchema(observationSchema);
ajv.addSchema(syncSchema);

const validateSyncRequest = ajv.getSchema<SyncRequest>(
  "https://birdcount.dev/schemas/sync.schema.json#/$defs/SyncRequest",
)!;

export interface ParseResult {
  request?: SyncRequest;
  errors?: string;
}

export function parseSyncRequest(body: string | undefined): ParseResult {
  if (!body) return { errors: "missing request body" };
  let json: unknown;
  try {
    json = JSON.parse(body);
  } catch {
    return { errors: "request body is not valid JSON" };
  }
  if (!validateSyncRequest(json)) {
    return { errors: ajv.errorsText(validateSyncRequest.errors) };
  }
  return { request: json as SyncRequest };
}
