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

const [observationListChange$, setObservationList] =
  createSignal<Observation[]>();
const [observations, observations$] = bind<Observation[]>(
  observationListChange$,
  observationList
);

observations$.subscribe(()=> {});


function addObservation(obs: Observation) {
  if( obs.parent) {
    if(!obs.parent.children) {
      obs.parent.children = [];
    }
    obs.parent.children.push(obs);
  }
  const newList = [...observationList, obs];

  window.localStorage.setItem("observations", JSON.stringify(serializeObservations(newList)));
  setObservationList(newList);
  setRecentObservationList(computeRecentObservations(newList));
}


observationListChange$.subscribe((c)=> {console.log(c, observationList)}); 

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

function serializeObservations(obsList: Observation[]) {
  const l = [];
  obsList.forEach((obs)=> {
    l.push(obs.toJSONObject());
  });
  return l;
}

function deserializeObservations(taxonomy: Taxonomy, json: any): Observation[] {
  const l: Observation[] = [];
  const lById: {[id: string]: Observation} = {};
  json.forEach((o)=> {
    let obs = new Observation();
    obs.fromJSONObject(taxonomy, o);
    l.push(obs);
    lById[obs.id] = o;
  });
  l.forEach((obs)=> {
    const parent = obs.parent;
    if(parent) {
      if(!parent.children) {
        parent.children = [];
      }
      parent.children.push(obs);
    }
  });
  return l;
}

try {
  const storage = window.localStorage.getItem("observations");
  if (storage) {
    const newList = deserializeObservations(taxonomy, JSON.parse(storage));
   // observationList = newList;
    setObservationList(newList);
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
  observations,
  recentObservations,
  clearObservations,
};
