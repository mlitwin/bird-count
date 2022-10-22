import Keypad from './Keypad';
import SpeciesPicker from './SpeciesPicker';
import Species from './common/Species';
import {checklist, latestObservation} from './store/store'

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
