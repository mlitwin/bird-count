import './App.css';
import Tab from 'react-bootstrap/Tab';
import Tabs from 'react-bootstrap/Tabs';

import ObservationEntry from './ObservationEntry';
import ObservationHistory from './ObservationHistory';

function App() {

  return (
    <div className="App">
      <header className="App-header">
      </header>
      <Tabs className="AppTabs">
        <Tab eventKey="home" title="Home">
          <ObservationEntry />
        </Tab>
        <Tab eventKey="history" title="History">
          <ObservationHistory />
        </Tab>
      </Tabs>
    </div>
  );
}

export default App;
