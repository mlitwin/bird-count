import { bind } from "@react-rxjs/core"
import { createSignal } from "@react-rxjs/utils"
//import species from '../data/species.json';
import taxonomy from '../data/taxonomy.json';
import checklistData from '../data/checklist.json';

const speciesTaxons = {};
taxonomy.species.forEach(sp => {
  speciesTaxons[sp.id] = sp;
});

let species = [];

checklistData.species.forEach(sp => {
  const tax = speciesTaxons[sp.id]
  let chsp = {...tax, ...sp};
  species.push(chsp);
});


const [checklistChange$, setChecklist] = createSignal();
const [checklist, text$] = bind(checklistChange$, species);

const [observationChange$, addObservation] = createSignal();
const [latestObservation] = bind(observationChange$, []);

const [observationListChange$, setObservationList] = createSignal();
const [observations, observations$] = bind(observationListChange$, []);


let observationList = [];

observationChange$.subscribe(observation => {
    observationList.push({
        createdAt: new Date(),
        species: observation
    });
    const newList = observationList.map(observation => observation)

    setObservationList(newList);
})


export {
    checklist,
    addObservation,
    latestObservation,
    observations
}