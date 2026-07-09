// summary.test.mjs — taxonomy decoration and export formatting.
// Aggregation semantics are server-side now; their drift gate lives in
// bird-count-backend (test/query.test.ts) and iOS (SchemaConformanceTests),
// both checking bird-count-schema/fixtures/derived/summary-cases.json.
//
// Run: npm test  (or: node --test test/)

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';
import { decorateSummary, exportCSV, exportText } from '../js/summary.js';

// The wire shape comes from the shared fixture so response-format drift fails here.
const FIXTURES = join(dirname(fileURLToPath(import.meta.url)), '../../bird-count-schema/fixtures');
const response = JSON.parse(readFileSync(join(FIXTURES, 'valid/summary-response.json'), 'utf8'));

const TAXONOMY = new Map([
  ['sonspa', { commonName: 'Song Sparrow', scientificName: 'Melospiza melodia' }],
  // amecro intentionally missing: falls back to the raw taxonId
]);

describe('decorateSummary', () => {
  it('maps known taxa to display names and totals through', () => {
    const summary = decorateSummary(response, TAXONOMY);
    assert.equal(summary.totalIndividuals, response.totalIndividuals);
    assert.equal(summary.totalSpecies, response.totalSpecies);
    assert.equal(summary.species[0].commonName, 'Song Sparrow');
    assert.equal(summary.species[0].scientificName, 'Melospiza melodia');
    assert.equal(summary.species[0].count, response.species[0].count);
  });

  it('falls back to the taxonId for unknown taxa', () => {
    const summary = decorateSummary(response, TAXONOMY);
    const unknown = summary.species.find(s => s.taxonId === 'amecro');
    assert.equal(unknown.commonName, 'amecro');
    assert.equal(unknown.scientificName, '');
  });
});

describe('exports', () => {
  const summary = decorateSummary(response, TAXONOMY);

  it('CSV has a header and one row per species', () => {
    const lines = exportCSV(summary).split('\n');
    assert.equal(lines[0], 'Common Name,Scientific Name,Count');
    assert.equal(lines.length, 1 + summary.species.length);
    assert.equal(lines[1], 'Song Sparrow,Melospiza melodia,2');
  });

  it('CSV escapes quotes and commas', () => {
    const tricky = decorateSummary(
      { totalIndividuals: 1, totalSpecies: 1, species: [{ taxonId: 'x', count: 1 }] },
      new Map([['x', { commonName: 'Say, "hi"', scientificName: 'S. hi' }]]),
    );
    assert.equal(exportCSV(tricky).split('\n')[1], '"Say, ""hi""",S. hi,1');
  });

  it('text export lists totals then species', () => {
    const lines = exportText(summary).split('\n');
    assert.equal(lines[0], `Total individuals: ${response.totalIndividuals}`);
    assert.equal(lines[1], `Total species: ${response.totalSpecies}`);
    assert.equal(lines[3], 'Song Sparrow: 2');
  });
});
