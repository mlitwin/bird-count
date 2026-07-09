// summary.js — decorate the server summary with taxonomy names + CSV/text export.
// Aggregation itself happens server-side (GET /v1/summary); the semantics are
// locked by bird-count-schema/fixtures/derived/summary-cases.json.

/**
 * Attach display names to a SummaryResponse.
 *
 * @param {{ totalIndividuals: number, totalSpecies: number, species: Object[] }} response
 * @param {Map<string, { commonName: string, scientificName: string }>} taxonomy
 * @returns {{ totalIndividuals: number, totalSpecies: number, species: Object[] }}
 */
export function decorateSummary(response, taxonomy) {
  return {
    totalIndividuals: response.totalIndividuals,
    totalSpecies: response.totalSpecies,
    species: response.species.map(({ taxonId, count }) => {
      const taxon = taxonomy.get(taxonId);
      return {
        taxonId,
        commonName: taxon?.commonName ?? taxonId,
        scientificName: taxon?.scientificName ?? '',
        count,
      };
    }),
  };
}

/**
 * Export summary as CSV (Common Name, Scientific Name, Count).
 * @param {ReturnType<decorateSummary>} summary
 * @returns {string}
 */
export function exportCSV(summary) {
  const rows = [
    'Common Name,Scientific Name,Count',
    ...summary.species.map(s =>
      `${csvEscape(s.commonName)},${csvEscape(s.scientificName)},${s.count}`
    ),
  ];
  return rows.join('\n');
}

/**
 * Export summary as plain text.
 * @param {ReturnType<decorateSummary>} summary
 * @returns {string}
 */
export function exportText(summary) {
  return [
    `Total individuals: ${summary.totalIndividuals}`,
    `Total species: ${summary.totalSpecies}`,
    '',
    ...summary.species.map(s => `${s.commonName}: ${s.count}`),
  ].join('\n');
}

function csvEscape(s) {
  if (/[",\n]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
  return s;
}
