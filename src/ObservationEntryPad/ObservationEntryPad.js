import Keypad from "./Keypad";
import SpeciesPicker from "./SpeciesPicker";
import FilterBar from "./FilterBar";
import SpeciesNavigation from "./SpeciesNavigation";
import { checklist } from "../store/store";
import { useState } from "react";

import "./ObservationEntryPad.css";

function ObservationEntryPad() {
  const [active, setActiveState] = useState(0);
  const [filter, setFilter] = useState("");

  function changeActive(delta) {
    let newActive = active + delta;
    if (newActive < 0 || newActive >= ck.length) {
      return;
    }
    setActiveState(newActive);
  }

  function setActive(newActive) {
    setActiveState(newActive);
  }

  const ck = checklist();
  return (
    <div className="ObservationEntryPad">
      <div className="ObservationListArea">
        <SpeciesNavigation changeActive={changeActive}></SpeciesNavigation>
        <SpeciesPicker species={ck} active={active} setActive={setActive} />
      </div>
      <FilterBar
        filter={filter}
        setFilter={setFilter}
        changeActive={changeActive}
      />
      <Keypad setFilter={setFilter} />
    </div>
  );
}

export default ObservationEntryPad;
