// app.js — wiring: auth, data fetch, range presets, render loop

import { config } from './config.js';
import { login, logout, isLoggedIn, handleCallback, accessToken } from './auth.js';
import { fetchAllObservations } from './api.js';
import { computeSummary, exportCSV, exportText } from './summary.js';

let allDTOs = [];
let taxonomy = new Map();
let lastSummary = null;

// -- Range presets --

function todayRange() {
  const now = new Date();
  const start = new Date(now);
  start.setHours(0, 0, 0, 0);
  return { begin: start.toISOString(), end: now.toISOString(), preset: 'today' };
}

function lastHourRange() {
  const now = new Date();
  return { begin: new Date(now - 3_600_000).toISOString(), end: now.toISOString(), preset: 'lastHour' };
}

function last7Range() {
  const now = new Date();
  return { begin: new Date(now - 7 * 86_400_000).toISOString(), end: now.toISOString(), preset: 'last7' };
}

function allTimeRange() {
  return { begin: new Date(0).toISOString(), end: new Date().toISOString(), preset: 'all' };
}

// -- DOM helpers --

function $(id) { return document.getElementById(id); }

function showSection(name) {
  for (const el of document.querySelectorAll('[data-section]')) {
    el.hidden = el.dataset.section !== name;
  }
}

function highlightPreset(preset) {
  for (const btn of document.querySelectorAll('.preset-btn')) {
    btn.classList.toggle('active', btn.dataset.preset === preset);
  }
  $('custom-range').hidden = preset !== 'custom';
}

function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function renderSummary(range) {
  const summary = computeSummary(allDTOs, range, taxonomy);
  lastSummary = summary;

  $('total-individuals').textContent = summary.totalIndividuals;
  $('total-species').textContent = summary.totalSpecies;

  const tbody = $('species-tbody');
  tbody.innerHTML = '';
  for (const row of summary.species) {
    const tr = document.createElement('tr');
    tr.innerHTML =
      `<td>${escapeHtml(row.commonName)}</td>` +
      `<td><em>${escapeHtml(row.scientificName)}</em></td>` +
      `<td class="count">${row.count}</td>`;
    tbody.appendChild(tr);
  }

  $('empty-msg').hidden = summary.species.length > 0;
}

// -- Export --

function download(filename, content, mime) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([content], { type: mime }));
  a.download = filename;
  a.click();
  URL.revokeObjectURL(a.href);
}

function dateTag() {
  return new Date().toISOString().slice(0, 10);
}

// -- Main --

async function main() {
  // Load taxonomy (best-effort; falls back to taxonId as display name)
  try {
    const res = await fetch('./taxonomy.json');
    if (res.ok) {
      const arr = await res.json();
      taxonomy = new Map(arr.map(t => [t.id, { commonName: t.commonName, scientificName: t.scientificName }]));
    }
  } catch (e) {
    console.warn('Taxonomy load failed', e);
  }

  // Handle OAuth callback before checking login state
  try {
    await handleCallback();
  } catch (e) {
    console.error('Auth callback error', e);
  }

  if (!isLoggedIn()) {
    showSection('signin');
    $('sign-in-btn').addEventListener('click', () => login());
    return;
  }

  showSection('app');
  $('sign-out-btn').addEventListener('click', () => logout());

  // Range preset buttons
  const presetFns = {
    'preset-today': todayRange,
    'preset-last-hour': lastHourRange,
    'preset-last-7': last7Range,
    'preset-all': allTimeRange,
  };

  let currentRange = todayRange();

  for (const [id, fn] of Object.entries(presetFns)) {
    const btn = $(id);
    if (!btn) continue;
    btn.addEventListener('click', () => {
      currentRange = fn();
      highlightPreset(currentRange.preset);
      if (allDTOs.length > 0) renderSummary(currentRange);
    });
  }

  $('preset-custom')?.addEventListener('click', () => {
    highlightPreset('custom');
  });

  $('apply-custom')?.addEventListener('click', () => {
    const begin = $('custom-begin').value;
    const end = $('custom-end').value;
    if (!begin || !end) return;
    currentRange = {
      begin: new Date(begin).toISOString(),
      end: new Date(end + 'T23:59:59').toISOString(),
      preset: 'custom',
    };
    if (allDTOs.length > 0) renderSummary(currentRange);
  });

  $('export-csv')?.addEventListener('click', () => {
    if (lastSummary) download(`bird-count-${dateTag()}.csv`, exportCSV(lastSummary), 'text/csv');
  });

  $('export-text')?.addEventListener('click', () => {
    if (lastSummary) download(`bird-count-${dateTag()}.txt`, exportText(lastSummary), 'text/plain');
  });

  // Fetch all observations
  $('loading').hidden = false;
  $('error-msg').hidden = true;
  try {
    const token = await accessToken();
    if (!token) { logout(); return; }
    allDTOs = await fetchAllObservations(token, config.apiBaseURL);
  } catch (e) {
    console.error('Fetch error', e);
    $('error-msg').textContent = 'Failed to load observations. Please refresh.';
    $('error-msg').hidden = false;
  } finally {
    $('loading').hidden = true;
  }

  highlightPreset('today');
  renderSummary(currentRange);
}

main();
