import Navbar from "react-bootstrap/Navbar";
import Keypad from "./Keypad";
import SpeciesPicker from "./SpeciesPicker";
import { checklist } from "../store/store";
import { useState } from "react";

function ObservationEntryPad() {
  const [active, setActiveState] = useState(0);

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
      <div>
        <SpeciesPicker species={ck} active={active} />
        <Keypad changeActive={changeActive} />
      </div>
    </div>
  );
}

export default ObservationEntryPad;
