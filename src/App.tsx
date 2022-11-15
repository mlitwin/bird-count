import React from "react";
import "./App.css";
import Tabs from "@mui/material/Tabs";
import Tab from "@mui/material/Tab";

import ObservationEntryPad from "./ObservationEntryPad";
import ObservationHistory from "./ObservationHistory";

function App() {
  const [value, setValue] = React.useState(0);

  const handleChange = (event: React.SyntheticEvent, newValue: number) => {
    setValue(newValue);
  };

  return (
    <div className="App">
      <Tabs className="AppHeader" value={value} onChange={handleChange}>
        <Tab label="Home" />
        <Tab label="History" />
      </Tabs>
      <div className="AppContent">
        <div hidden={value !== 0}>
          <ObservationEntryPad />
        </div>
        <div hidden={value !== 1}>
          <ObservationHistory />
        </div>
      </div>
    </div>
  );
  /*
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
  */
}

export { App };
