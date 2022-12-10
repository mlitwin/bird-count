import * as React from "react";
import Button from "@mui/material/Button";
import Observations from "./Observations";
import { observations, clearObservations } from "./store/store";

function ObservationHistory() {
  const obs = observations();
  const parentObs = obs.filter(o => o.parent == null);
  const olist = parentObs.map(o => o.toJSONObject());
  const mail = encodeURIComponent(JSON.stringify(olist, null, 2));
  const mailto = `mailto:?body=${mail}&subject=Email the List`;

  function doClear() {
    clearObservations();
  }

  return (
    <div className="oneColumn">
      <Observations observations={parentObs} />
      <Button variant="contained" onClick={(e) => doClear()}>
        CLEAR
      </Button>
      <a href={mailto}>Email the List</a>
    </div>
  );
}

export default ObservationHistory;
