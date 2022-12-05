import React, { useState } from "react";
import { BehaviorSubject  } from "rxjs";
//import { BehaviorSubject as Observable } from "rxjs";
import { bind } from "@react-rxjs/core";
import { createSignal } from "@react-rxjs/utils";
import {
  Observation,
  Taxonomy,
  Checklist,
  Species,
  ObservationSet,
} from "../model/types";

import taxonomyJSON from "../data/taxonomy.json";
import chk from "../data/checklist.json";
import { withLatestFrom, map , switchMap, last} from "rxjs";

const taxonomy = new Taxonomy(taxonomyJSON.id);
taxonomy.addSpecies(taxonomyJSON.species as Species[]);

let curChecklist = new Checklist(taxonomy);
curChecklist.setFilters(chk);
let observationList = [];

const [checklistChange$, setChecklist] = createSignal<Checklist>();
const [checklist, checklist$] = bind<Checklist>(checklistChange$, null);

checklist$.subscribe((c) => {}); // Force subscription so we can be sure new events won't be lost. Must be me not undersanding ther React way ...
setChecklist(curChecklist);

const [observationListChange$, setObservationList] =
  createSignal<Observation[]>();
const [observations, observations$] = bind<Observation[]>(
  observationListChange$,
  observationList
);

observations$.subscribe(() => {});

const [observationAdded$, signalAddedObservation] = createSignal<Observation>();

observationAdded$.subscribe((obs) => {
  // console.log(obs);
});

// Pass in current observations to avoid call to observations() hook outside of React function
function addObservation(curObservations: Observation[], obs: Observation) {
  if (obs.parent) {
    if (!obs.parent.children) {
      obs.parent.children = [];
    }
    obs.parent.children.push(obs);
  }
  const newList = [...curObservations, obs];

  window.localStorage.setItem(
    "observations",
    JSON.stringify(serializeObservations(newList))
  );
  setObservationList(newList);
  setRecentObservationList(computeRecentObservations(newList));
  signalAddedObservation(obs);
}

const [recentObservationListChange$, setRecentObservationList] =
  createSignal<Observation[]>();
observationListChange$.subscribe(() => {});

const [recentObservations] = bind<any>(
  recentObservationListChange$,
  computeRecentObservations(observationList)
);

function clearObservations() {
  window.localStorage.removeItem("observations");
  //observationList = [];
  setObservationList([]);
}

function serializeObservations(obsList: Observation[]) {
  const l = [];
  obsList.forEach((obs) => {
    l.push(obs.toJSONObject());
  });
  return l;
}

function deserializeObservations(taxonomy: Taxonomy, json: any): Observation[] {
  const l: Observation[] = [];
  const lById: { [id: string]: Observation } = {};
  json.forEach((o) => {
    let obs = new Observation();
    obs.fromJSONObject(taxonomy, o);
    l.push(obs);
    lById[obs.id] = o;
  });
  l.forEach((obs) => {
    const parent = obs.parent;
    if (parent) {
      if (!parent.children) {
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

/*

function createObservationQuery(predicate: (Observation) => boolean) {
  return observations$.pipe(
    map((list) => {
    //  console.log(list);
      const obsSet = new ObservationSet(taxonomy, list);
     // console.log(obsSet);
      return obsSet;
    }));
}

function useObservationQuery(predicate: (Observation) => boolean) {
  

  const [observable, observable$] = useState(createObservationQuery(predicate));
  const handleNext = value => {
    observable.next(value);
  };

  return [observable, handleNext];

  return useState(createObservationQuery(predicate));

 // query$.subscribe(()=>{});

 // return [query];
  /*

observationAdded$.subscribe(obs => {
  console.log(obs);
})

}*/

function useObservationQuery(predicate: (Observation) => boolean) {
  const obsSet = new ObservationSet(taxonomy, observations().filter(predicate));
    const [query, setQuery] = useState(obsSet);

    return query;
}
export {
  checklist,
  addObservation,
  observations,
  recentObservations,
  clearObservations,
  useObservationQuery,
};
