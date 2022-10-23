import Navbar from 'react-bootstrap/Navbar';
import Keypad from './Keypad';
import SpeciesPicker from './SpeciesPicker';
import Species from './common/Species';
import {checklist, latestObservation} from './store/store'
import Container from 'react-bootstrap/Container';
import { Nav } from 'react-bootstrap';

function ObservationEntry() {

  const ck = checklist();
  const latest = latestObservation();
  return (
    <div className="App">
      <header className="App-header">
      </header>
      <div>
        <Species species={latest} />
        <SpeciesPicker species={ck} />
        <Keypad />
      </div>
    </div>
  );
}

export default ObservationEntry;
