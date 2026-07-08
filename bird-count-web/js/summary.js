// summary.js — aggregate ledger counts into a display summary + CSV/text export

import { countsInRange } from './ledger.js';

/**
 * Compute a display summary for the given DTOs and date range.
 *
 * @param {Object[]} dtos - flat observation DTOs
 * @param {{ begin: string, end: string }} range
 * @param {Map<string, { commonName: string, scientificName: string }>} taxonomy
 * @returns {{ totalIndividuals: number, totalSpecies: number, species: Object[] }}
 */
export function computeSummary(dtos, range, taxonomy) {
  const counts = countsInRange(dtos, range);

  const species = [...counts.entries()]
    .map(([taxonId, count]) => {
      const taxon = taxonomy.get(taxonId);
      return {
        taxonId,
        commonName: taxon?.commonName ?? taxonId,
        scientificName: taxon?.scientificName ?? '',
        count,
      };
    })
    .sort((a, b) => b.count - a.count || a.commonName.localeCompare(b.commonName));

  return {
    totalIndividuals: species.reduce((s, r) => s + r.count, 0),
    totalSpecies: species.length,
    species,
  };
}

/**
 * Export summary as CSV (Common Name, Scientific Name, Count).
 * @param {ReturnType<computeSummary>} summary
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
 * @param {ReturnType<computeSummary>} summary
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
