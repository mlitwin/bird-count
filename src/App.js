import './App.css';

import Keypad from './Keypad';
import Observations from './Observations';
import SpeciesPicker from './SpeciesPicker';
import {checklist, observations} from './store/store'

function App() {

  const ck = checklist();
  const obs = observations();
  console.log(obs);
  return (
    <div className="App">
      <header className="App-header">
      </header>
      <div>
        <Observations observations={obs} />
        <SpeciesPicker species={ck} />
        <Keypad />
      </div>
    </div>
  );
}

export default App;
