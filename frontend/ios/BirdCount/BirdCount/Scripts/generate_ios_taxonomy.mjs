#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
// Script lives at repo/frontend/ios/BirdCount/BirdCount/Scripts
// repoRoot = __dirname/../../../../..
const repoRoot = resolve(__dirname, '../../../../../');
const sourceTaxonomy = resolve(repoRoot, 'taxonomy/taxonomy.json');
const out = resolve(__dirname, '../Resources/ios_taxonomy_min.json');

try {
    const raw = JSON.parse(readFileSync(sourceTaxonomy, 'utf8'));
    const species = raw.species || [];
    const minimal = species
        .filter(s => s.type === 'species')
        .map(s => ({
            id: s.id,
            commonName: s.localizations?.en?.commonName || s.sciName,
            scientificName: s.sciName,
            order: s.taxonomicOrder || 0,
            rank: 'species'
        }))
        .sort((a, b) => a.order - b.order);
    writeFileSync(out, JSON.stringify(minimal, null, 2));
    console.log(`Wrote ${minimal.length} species to ${out}`);
} catch (e) {
    console.error('Failed generating taxonomy:', e.message);
    process.exit(1);
}
