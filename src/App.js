import "./App.css";
import Tab from "react-bootstrap/Tab";
import Nav from "react-bootstrap/Nav";

import ObservationEntryPad from "./ObservationEntryPad/ObservationEntryPad";
import ObservationHistory from "./ObservationHistory";
import Observation from "./common/Observation";

import { latestObservation } from "./store/store";

function App() {
  const latest = latestObservation();

  return (
    <Tab.Container className="AppContainer" defaultActiveKey="first">
      <Tab.Content className="AppContent">
        <Tab.Pane eventKey="first">
          <ObservationEntryPad />
        </Tab.Pane>
        <Tab.Pane eventKey="second">
          <ObservationHistory />
        </Tab.Pane>
      </Tab.Content>
      <Nav className="AppHeader">
        <Nav.Item>
          <Nav.Link eventKey="first">Home</Nav.Link>
        </Nav.Item>
        <Nav.Item>
          <Nav.Link eventKey="second">History</Nav.Link>
        </Nav.Item>
        <Observation observation={latest} />
      </Nav>
    </Tab.Container>
  );
}

export default App;
