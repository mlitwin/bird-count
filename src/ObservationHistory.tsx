import * as React from "react";
import Button from "@mui/material/Button";
import Observations from "./Observations";
import { observations, clearObservations } from "./store/store";

function ObservationHistory() {
  const obs = observations();
  console.log(obs);
  const mail = encodeURIComponent(JSON.stringify(obs, null, 2));
  const mailto = `mailto:?body=${mail}&subject=Email the List`;

  function doClear() {
    clearObservations();
  }
  return (
    <div className="oneColumn">
      <Observations observations={obs} />
      <Button variant="contained" onClick={(e) => doClear()}>
        CLEAR
      </Button>
      <a href={mailto}>Email the List</a>
    </div>
  );
}

export default ObservationHistory;
