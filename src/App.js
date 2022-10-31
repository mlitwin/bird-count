import "./App.css";
import Tab from "react-bootstrap/Tab";
import Nav from "react-bootstrap/Nav";

import ObservationEntryPad from "./ObservationEntryPad/ObservationEntryPad";
import ObservationHistory from "./ObservationHistory";
import Species from "./common/Species";

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
        <Species species={latest} />
      </Nav>
    </Tab.Container>
  );
}

export default App;
