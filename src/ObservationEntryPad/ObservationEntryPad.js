import Keypad from "./Keypad";
import SpeciesPicker from "./SpeciesPicker";
import FilterBar from "./FilterBar";
import SpeciesNavigation from "./SpeciesNavigation";
import { checklist, addObservation } from "../store/store";
import { useState } from "react";

import "./ObservationEntryPad.css";

function ObservationEntryPad() {
  const [active, setActiveState] = useState(0);
  const [filter, setFilter] = useState("");
  const ck = checklist();

  function changeActive(delta) {
    let newActive = active + delta;
    if (newActive < 0 || newActive >= ck.length) {
      return;
    }
    setActiveState(newActive);
  }

  function chooseItem(index) {
    if (index === undefined) {
      index = active;
    }
    addObservation(ck[index]);
    setActiveState(index);
  }


  return (
    <div className="ObservationEntryPad">
      <div className="ObservationListArea">
        <SpeciesNavigation changeActive={changeActive}></SpeciesNavigation>
        <SpeciesPicker species={ck} active={active} chooseItem={chooseItem} />
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
