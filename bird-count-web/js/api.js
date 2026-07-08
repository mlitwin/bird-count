// api.js — paginated fetch of all observations from /v1/observations.

/**
 * Fetch every observation DTO from the API using cursor-based pagination.
 * @param {string} token - Bearer access token
 * @param {string} apiBaseURL - e.g. "https://xxx.execute-api.us-east-1.amazonaws.com/v1"
 * @returns {Promise<Object[]>} flat array of ObservationRecordDTOs
 */
export async function fetchAllObservations(token, apiBaseURL) {
  const dtos = [];
  let cursor = '0';

  while (true) {
    const url = new URL(`${apiBaseURL}/observations`);
    url.searchParams.set('since', cursor);
    url.searchParams.set('limit', '200');

    const res = await fetch(url.toString(), {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) throw new Error(`API error ${res.status}: ${await res.text()}`);

    const body = await res.json();
    dtos.push(...(body.changes ?? []));

    if (!body.hasMore) break;
    cursor = body.cursor;
  }

  return dtos;
}
