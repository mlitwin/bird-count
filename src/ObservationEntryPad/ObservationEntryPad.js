import Keypad from "./Keypad";
import SpeciesPicker from "./SpeciesPicker";
import FilterBar from "./FilterBar";
import SpeciesNavigation from "./SpeciesNavigation";
import { v4 as uuidv4 } from "uuid";
import { checklist, addObservation, recentObservations } from "../store/store";
import { useState } from "react";

import "./ObservationEntryPad.css";

function passessFilter(filter, species) {
  if (filter === "") {
    return true;
  }
  const f = filter.toUpperCase();
  for (let i = 0; i < species.abbreviations.length; i++) {
    const abbrv = species.abbreviations[i];
    if (abbrv.startsWith(f)) {
      return true;
    }
  }

  return false;
}

function computeChecklist(filter) {
  const ck = checklist();
  let species = [];

  ck.forEach((s) => {
    if (passessFilter(filter, s)) {
      species.push(s);
    }
  });

  // Recent ones first
  const recent = recentObservations();
  const recentOrder = {};
  let recentIndex = 1;
  recent.forEach((obs) => {
    if (!(obs.species.id in recentOrder)) {
      recentOrder[obs.species.id] = recentIndex;
      recentIndex++;
    }
  });

  species = species.sort((a, b) => {
    let aIndex = a.taxonomicOrder;
    let bIndex = b.taxonomicOrder;

    if (a.id in recentOrder) {
      aIndex = -(recent.length - recentOrder[a.id]);
    }
    if (b.id in recentOrder) {
      bIndex = -(recent.length - recentOrder[b.id]);
    }

    return aIndex - bIndex;
  });

  return species;
}

function ObservationEntryPad() {
  const [active, setActiveState] = useState(0);
  const [filter, setFilter] = useState("");

  const species = computeChecklist(filter);

  function changeActive(delta) {
    let newActive = active + delta;
    if (newActive < 0 || newActive >= species.length) {
      return;
    }
    setActiveState(newActive);
  }

  function resetInput() {
    setFilter("");
    setActiveState(0);
  }

  function chooseItem(index) {
    if (species.length === 0) {
      return;
    }

    if (index === undefined) {
      index = active;
    }
    const now = Date.now();
    const observation = {
      id: uuidv4(),
      createdAt: now,
      species: species[index],
    };
    addObservation(observation);
    resetInput();
  }

  return (
    <div className="ObservationEntryPad oneColumn">
      <div className="ObservationListArea oneColumnExpand">
       <SpeciesPicker
          species={species}
          active={active}
          chooseItem={chooseItem}
        />

      </div>
      <FilterBar
        filter={filter}
        setFilter={setFilter}
        chooseItem={chooseItem}
      />
      <Keypad filter={filter} setFilter={setFilter} />
    </div>
  );
}

export default ObservationEntryPad;
