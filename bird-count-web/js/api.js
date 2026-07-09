// api.js — server-side query calls (aggregation happens in the Lambda).

async function get(token, apiBaseURL, path, params) {
  const base = apiBaseURL.replace(/\/$/, '');
  const url = new URL(`${base}${path}`);
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined) url.searchParams.set(k, v);
  }
  const res = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error(`API error ${res.status}: ${await res.text()}`);
  return res.json();
}

/**
 * Fetch the range summary from GET /v1/summary.
 * @param {string} token - Bearer access token
 * @param {string} apiBaseURL - e.g. "https://xxx.execute-api.us-east-1.amazonaws.com/v1"
 * @param {{ begin: string, end: string }} range - ISO 8601
 * @returns {Promise<Object>} SummaryResponse (see bird-count-schema query.schema.json)
 */
export function fetchSummary(token, apiBaseURL, range) {
  return get(token, apiBaseURL, '/summary', { begin: range.begin, end: range.end });
}
