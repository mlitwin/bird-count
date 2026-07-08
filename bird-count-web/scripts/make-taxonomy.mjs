#!/usr/bin/env node
// Trims ios_taxonomy_min.json down to [{id, commonName, scientificName}] for the web viewer.
// Usage (from bird-count-web/): node scripts/make-taxonomy.mjs

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const src = join(__dirname, '../../bird-count-ios/BirdCount/Resources/ios_taxonomy_min.json');
const out = join(__dirname, '../taxonomy.json');

const raw = JSON.parse(readFileSync(src, 'utf8'));
const trimmed = raw.map(({ id, commonName, scientificName }) => ({ id, commonName, scientificName }));
writeFileSync(out, JSON.stringify(trimmed));
console.log(`Wrote ${trimmed.length} taxa → taxonomy.json`);
