import Keypad from "./Keypad";
import SpeciesPicker from "./SpeciesPicker";
import FilterBar from "./FilterBar";
import SpeciesNavigation from "./SpeciesNavigation";
import { checklist, addObservation } from "../store/store";
import { useState } from "react";

import "./ObservationEntryPad.css";

function passessFilter(filter, species) {
  if (filter === "") {
    return true;
  }
  const f = filter.toUpperCase();
  for(let i=0; i < species.abbreviations.length; i++) {
    const abbrv = species.abbreviations[i];
    if(abbrv.startsWith(f)) {
      return true;
    }
  }

  return false;
}

function ObservationEntryPad() {
  const [active, setActiveState] = useState(0);
  const [filter, setFilter] = useState("");
  const ck = checklist();
  let species = [];

  ck.forEach((s) => {
    if (passessFilter(filter, s)) {
      species.push(s);
    }
  });

  function changeActive(delta) {
    let newActive = active + delta;
    if (newActive < 0 || newActive >= species.length) {
      return;
    }
    setActiveState(newActive);
  }

  function chooseItem(index) {
    if (species.length === 0) {
      return;
    }
    
    if (index === undefined) {
      index = active;
    }
    addObservation(species[index]);
    setActiveState(index);
  }

  return (
    <div className="ObservationEntryPad">
      <div className="ObservationListArea">
        <SpeciesNavigation changeActive={changeActive}></SpeciesNavigation>
        <SpeciesPicker species={species} active={active} chooseItem={chooseItem} />
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
