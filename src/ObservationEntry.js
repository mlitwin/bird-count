import Navbar from 'react-bootstrap/Navbar';
import Keypad from './Keypad';
import SpeciesPicker from './SpeciesPicker';
import Species from './common/Species';
import {checklist, latestObservation} from './store/store'
import Container from 'react-bootstrap/Container';
import { Nav } from 'react-bootstrap';
import { useState } from 'react';


function ObservationEntry() {

  const [active, setActiveState] = useState(0);

  function changeActive(delta) {
    let newActive = active + delta;
    if (newActive < 0 || newActive >= ck.length) {
        return;
    }
    setActiveState(newActive);
  }
  const ck = checklist();
  const latest = latestObservation();
  return (
    <div className="App">
      <header className="App-header">
      </header>
      <div>
        <Species species={latest} />
        <SpeciesPicker species={ck} active={active} />
        <Keypad changeActive={changeActive} />
      </div>
    </div>
  );
}

export default ObservationEntry;
