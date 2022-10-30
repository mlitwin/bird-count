import { bind } from "@react-rxjs/core";
import { createSignal } from "@react-rxjs/utils";
import { v4 as uuidv4 } from "uuid";

import taxonomy from "../data/taxonomy.json";
import checklistData from "../data/checklist.json";

const speciesTaxons = {};
taxonomy.species.forEach((sp) => {
  speciesTaxons[sp.id] = sp;
});

let species = [];

function addAbbeviations(species) {
  let abbrv = [];

  abbrv.push(species.code.toUpperCase());
  const name = species.name
    .replaceAll(/[^\w- '/]/g, "")
    .replaceAll(/[^\w]/g, " ")
    .split(/\s+/)
    .map((w) => w[0])
    .join("")
    .toUpperCase();

  abbrv.push(name);

  species.abbreviations = abbrv;
}

checklistData.species.forEach((sp) => {
  const tax = speciesTaxons[sp.id];
  let chsp = { ...tax, ...sp };
  addAbbeviations(chsp);
  species.push(chsp);
});

const [checklistChange$, _setChecklist] = createSignal();
const [checklist, _checklist$] = bind(checklistChange$, species);

const [observationChange$, addObservation] = createSignal();
const [latestObservation] = bind(observationChange$, []);

const [observationListChange$, setObservationList] = createSignal();
const [observations, _observations$] = bind(observationListChange$, []);

const [recentObservationListChange$, setRecentObservationList] = createSignal();

const [recentObservations] = bind(recentObservationListChange$, []);

let observationList = [];

observationChange$.subscribe((observation) => {
  const now = new Date();
  observationList.push({
    id: uuidv4(),
    createdAt: now,
    species: observation,
  });
  const newList = observationList.map((observation) => observation);
  setObservationList(newList);
  const day = 24*60*60;
  const recentList = newList.filter((obs) => obs.createdAt >= (now - day))
    .sort((a,b) => b.createdAt - a.createdAt);
  setRecentObservationList(recentList)
});

export { checklist, addObservation, latestObservation, observations, recentObservations};
