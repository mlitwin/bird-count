import { bind} from "@react-rxjs/core";
import { createSignal } from "@react-rxjs/utils";
import { Observation, Taxonomy, Checklist, Species } from "../model/types";

import taxonomyJSON from "../data/taxonomy.json";
import chk from "../data/checklist.json";


const taxonomy = new Taxonomy(taxonomyJSON.id);
taxonomy.addSpecies(taxonomyJSON.species as Species[]);

let curChecklist = new Checklist(taxonomy);
curChecklist.setFilters(chk);
let observationList = [];

const [checklistChange$, setChecklist] = createSignal<Species[]>();
const [checklist, checklist$] = bind<Species[]>(checklistChange$, []);

checklist$.subscribe((c)=> {}); // Force subscription so we can be sure new events won't be lost. Must be me not undersanding ther React way ...
setChecklist(curChecklist.species);

const [observationChange$, addObservation] = createSignal<Observation>();
const [latestObservation] = bind(observationChange$, null);

const [observationListChange$, setObservationList] =
  createSignal<Observation[]>();
const [observations] = bind<Observation[]>(
  observationListChange$,
  observationList
);

const [recentObservationListChange$, setRecentObservationList] =
  createSignal<Observation[]>();

const [recentObservations] = bind<any>(
  recentObservationListChange$,
  computeRecentObservations(observationList)
);

function clearObservations() {
  window.localStorage.removeItem("observations");
  observationList = [];
  setObservationList(observationList);
}

observationChange$.subscribe((observation: Observation) => {
  observationList.push(observation);
  window.localStorage.setItem("observations", JSON.stringify(observationList));
  const newList = observationList.map((observation) => observation);
  setObservationList(newList);
  setRecentObservationList(computeRecentObservations(newList));
});

try {
  const storage = window.localStorage.getItem("observations");
  if (storage) {
    observationList = JSON.parse(storage);
  }
} catch (e) {}

function computeRecentObservations(list, now?: number) {
  if (!now) {
    now = Date.now();
  }
  const day = 24 * 60 * 60 * 1000;
  const recentList = list
    .filter((obs) => obs.createdAt >= now - day)
    .sort((a, b) => b.createdAt - a.createdAt);

  return recentList;
}

export {
  checklist,
  addObservation,
  latestObservation,
  observations,
  recentObservations,
  clearObservations,
};
