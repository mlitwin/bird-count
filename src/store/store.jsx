import { bind } from "@react-rxjs/core";
import { createSignal } from "@react-rxjs/utils";
import { v4 as uuidv4 } from "uuid";

import taxonomy from "../data/taxonomy.json";
import chk from "../data/checklist.json";

const speciesTaxons = {};
taxonomy.species.forEach((sp) => {
  speciesTaxons[sp.id] = sp;
});

let species = [];

function addAbbeviations(species) {
  let abbrv = [];
  const commonName = species.localizations.en.commonName.toUpperCase();

  const name = commonName
    .replaceAll(/[^\w- /]/g, "")
    .replaceAll(/[^\w]/g, " ")
    .split(/\s+/)
    .map((w) => w[0])
    .join("");

  abbrv.push(name);
  abbrv.push(commonName.replaceAll(/[^\w]/g, ""));

  species.abbreviations = abbrv;
}

function testFilter(sp) {
  switch (sp.type) {
    case "hybrid":
    case "slash":
    case "issf":
    case "intergrade":
    case "form":
      return false;
  }

  return true;
}

for (let id in chk.species) {
  const sp = chk.species[id];
  const tax = speciesTaxons[id];
  let chsp = { ...tax, ...sp };
  if (testFilter(chsp)) {
    addAbbeviations(chsp);
    species.push(chsp);
  }
}

let observationList = [];
try {
  const storage = window.localStorage.getItem("observations");
  if (storage) {
    observationList = JSON.parse(storage);
  }
} catch (e) {}

function computeRecentObservations(list, now) {
  if (!now) {
    now = Date.now();
  }
  const day = 24 * 60 * 60 * 1000;
  const recentList = list
    .filter((obs) => obs.createdAt >= now - day)
    .sort((a, b) => b.createdAt - a.createdAt);

  return recentList;
}

const [checklistChange$, _setChecklist] = createSignal();
const [checklist, _checklist$] = bind(checklistChange$, species);

const [observationChange$, addObservation] = createSignal();
const [latestObservation] = bind(observationChange$, null);

const [observationListChange$, setObservationList] = createSignal();
const [observations, _observations$] = bind(
  observationListChange$,
  observationList
);

const [recentObservationListChange$, setRecentObservationList] = createSignal();

const [recentObservations] = bind(
  recentObservationListChange$,
  computeRecentObservations(observationList)
);

function clearObservations() {
  window.localStorage.removeItem("observations");
  observationList = [];
  setObservationList(observationList);
}

observationChange$.subscribe((observation) => {
  const now = Date.now();
  observationList.push({
    id: uuidv4(),
    createdAt: now,
    species: observation,
  });
  window.localStorage.setItem("observations", JSON.stringify(observationList));
  const newList = observationList.map((observation) => observation);
  setObservationList(newList);
  setRecentObservationList(computeRecentObservations(newList));
});

export {
  checklist,
  addObservation,
  latestObservation,
  observations,
  recentObservations,
  clearObservations,
};
