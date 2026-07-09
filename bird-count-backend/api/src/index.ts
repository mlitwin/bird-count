import type { APIGatewayProxyEventV2WithJWTAuthorizer, APIGatewayProxyResultV2 } from "aws-lambda";
import { docClient } from "./dynamo.js";
import { parseSyncRequest } from "./validate.js";
import { pull, sync, SCOPE } from "./sync.js";
import { computeSummary, queryObservations, refreshLedger, validateRange } from "./ledger.js";

const SUPPORTED_SCHEMA_VERSION = 2;

const doc = docClient();

function json(statusCode: number, body: unknown): APIGatewayProxyResultV2 {
  return {
    statusCode,
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  };
}

function subOf(event: APIGatewayProxyEventV2WithJWTAuthorizer): string | undefined {
  const sub = event.requestContext.authorizer?.jwt?.claims?.sub;
  return typeof sub === "string" ? sub : undefined;
}

export async function handler(
  event: APIGatewayProxyEventV2WithJWTAuthorizer,
): Promise<APIGatewayProxyResultV2> {
  const route = `${event.requestContext.http.method} ${event.rawPath}`;

  if (route === "GET /v1/health") {
    return json(200, { ok: true });
  }

  // JWT authorizer runs before us on the remaining routes; sub is the identity.
  const sub = subOf(event);
  if (!sub) return json(401, { error: "unauthorized" });

  if (route === "POST /v1/sync") {
    const { request, errors } = parseSyncRequest(event.body);
    if (!request) return json(400, { error: errors });
    if (request.schemaVersion > SUPPORTED_SCHEMA_VERSION) {
      return json(400, { error: `unsupported schemaVersion ${request.schemaVersion}; server supports ${SUPPORTED_SCHEMA_VERSION}` });
    }
    return json(200, await sync(doc, request, sub));
  }

  if (route === "GET /v1/observations") {
    const since = event.queryStringParameters?.since;
    const limit = Math.min(Number(event.queryStringParameters?.limit ?? "200") || 200, 200);
    return json(200, await pull(doc, since, limit));
  }

  if (route === "GET /v1/summary") {
    const q = event.queryStringParameters ?? {};
    const rangeError = validateRange(q.begin, q.end);
    if (rangeError) return json(400, { error: rangeError });
    const ledger = await refreshLedger(doc, SCOPE);
    return json(200, computeSummary(ledger.records.values(), q.begin!, q.end!));
  }

  if (route === "GET /v1/observations/query") {
    const q = event.queryStringParameters ?? {};
    const rangeError = validateRange(q.begin, q.end);
    if (rangeError) return json(400, { error: rangeError });
    const limit = Math.min(Math.max(Number(q.limit ?? "50") || 50, 1), 200);
    const ledger = await refreshLedger(doc, SCOPE);
    return json(200, queryObservations(ledger.records.values(), {
      begin: q.begin!,
      end: q.end!,
      taxonId: q.taxonId,
      limit,
      cursor: q.cursor,
    }));
  }

  return json(404, { error: `no route for ${route}` });
}
