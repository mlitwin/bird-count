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
      <Tabs
        variant="fullWidth"
        className="AppHeader"
        value={value}
        onChange={handleChange}
      >
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
}

export { App };
