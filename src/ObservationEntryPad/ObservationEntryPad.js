import Keypad from "./Keypad";
import SpeciesPicker from "./SpeciesPicker";
import FilterBar from "./FilterBar";
import { checklist } from "../store/store";
import { useState } from "react";

import './ObservationEntryPad.css';

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

  const ck = checklist();
  return (
    <div className="ObservationEntryPad">
      <SpeciesPicker species={ck} active={active} />
      <FilterBar
        filter={filter}
        setFilter={setFilter}
        changeActive={changeActive}
      />
      <Keypad changeActive={changeActive} />
    </div>
  );
}

export default ObservationEntryPad;
