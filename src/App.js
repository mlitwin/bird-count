import './App.css';
import Tab from 'react-bootstrap/Tab';
import Tabs from 'react-bootstrap/Tabs';
import Nav from 'react-bootstrap/Nav';

import ObservationEntry from './ObservationEntry';
import ObservationHistory from './ObservationHistory';
import Species from './common/Species';

import {latestObservation} from './store/store'


function App() {

  const latest = latestObservation();

  return (
    <Tab.Container className="AppContainer" defaultActiveKey="first">
      <Nav className="AppHeader">
        <Nav.Item>
          <Nav.Link eventKey="first">Home</Nav.Link>
        </Nav.Item>
        <Nav.Item>
          <Nav.Link eventKey="second">History</Nav.Link>
        </Nav.Item>
        <Species species={latest} />
      </Nav>
      <Tab.Content className="AppContent">
            <Tab.Pane eventKey="first">
              <ObservationEntry />
            </Tab.Pane>
            <Tab.Pane eventKey="second">
              <ObservationHistory />
            </Tab.Pane>
          </Tab.Content>
    </Tab.Container>
  )
  /*
  return (
    <div className="App">
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
  */
}

export default App;
