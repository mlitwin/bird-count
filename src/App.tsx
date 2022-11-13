import React from "react";
import "./App.css";
import Tab from "react-bootstrap/Tab";
import Nav from "react-bootstrap/Nav";

import ObservationEntryPad from "./ObservationEntryPad";
import ObservationHistory from "./ObservationHistory";

function App() {

  return (
    <Tab.Container defaultActiveKey="first">
            <Nav className="AppHeader">
        <Nav.Item>
          <Nav.Link eventKey="first">Home</Nav.Link>
        </Nav.Item>
        <Nav.Item>
          <Nav.Link eventKey="second">History</Nav.Link>
        </Nav.Item>
      </Nav>
      <Tab.Content className="AppContent">
        <Tab.Pane eventKey="first">
          <ObservationEntryPad />
        </Tab.Pane>
        <Tab.Pane eventKey="second">
          <ObservationHistory />
        </Tab.Pane>
      </Tab.Content>
    </Tab.Container>
  );
}

export {App};
