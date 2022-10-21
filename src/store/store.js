import { bind } from "@react-rxjs/core"
import { createSignal } from "@react-rxjs/utils"

// https://www.pwrc.usgs.gov/bbl/manual/speclist.cfm
const species = [
    { code: 'WEGR',
      name: 'Western Grebe'
    },
    { code: 'CLGR',
    name: 'Clark\'s Grebe'
  } 
  ];


const [checklistChange$, setChecklist] = createSignal();
const [checklist, text$] = bind(checklistChange$, species);

const [observationChange$, addObservation] = createSignal();
//const [latestObservation, observations$] = bind(observationChange$, []);

const [observationListChange$, setObservationList] = createSignal();
const [observations, observations$] = bind(observationListChange$, []);


let observationList = [];

observationChange$.subscribe(observation => {
    observationList.push({
        createdAt: new Date(),
        species: observation
    });
    const newList = observationList.map(observation => observation)

   // console.log(observationList);
    setObservationList(newList);
})


export {
    checklist,
    addObservation,
    observations
}