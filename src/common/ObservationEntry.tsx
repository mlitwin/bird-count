import React, { useState, useEffect } from "react";
import SpeciesName from "./SpeciesName";
import MoreMenu from "./ObservationEntry/MoreMenu";
import { Observation, Species } from "model/types";
import IconButton from "@mui/material/IconButton";
import {
  CheckCircleOutline,
  AddCircleOutline,
  RemoveCircleOutlined,
} from "@mui/icons-material";

import {
  addObservation
} from "../store/store";

import { v4 as uuidv4 } from "uuid";


import "./ObservationEntry.css";

type Modes = "empty" | "display" | "edit" | "create";
type Completion = "accept" | "cancel"

interface ObservationProps {
  observation: Observation;
  initialMode: Modes;
  onComplete?: (compltion: Completion) => void
}

function createObservation(species: Species) {
  const now = Date.now();
  const observation = {
    id: uuidv4(),
    createdAt: now,
    species,
    count: 1
  };
  
  return observation;
}

function ObservationEntry(props: ObservationProps) {
  const observation = props.observation;
  const [mode, setMode] = useState<Modes>(props.initialMode);
  const currentObservationId = observation ? observation.id : null;
  const [observationId, setObservationId] = useState(currentObservationId);
  const currentCount = observation ? observation.count : 0;
  const [count, setCount] = useState(currentCount);


  if (currentObservationId !== observationId) {
    setMode(props.initialMode);
    setObservationId(currentObservationId);
    setCount(currentCount);
  }

  if (mode === "empty" || !observation) {
    return <div className="ObservationSummary placeholder"></div>;
  }

  if (mode === "display") {
    return (
      <div className="Observation display">
        <div className="ObservationHeader">
         <div className="ObservationCount">{observation.count}</div>
          <SpeciesName species={observation.species}></SpeciesName>
        </div>
      </div>
    );  
  }

  function doAccept() {
    observation.count = count;
    addObservation(observation);
    setMode("display");
    if(props.onComplete) {
      props.onComplete("accept");
    }
  }

  function doCancel() {
    if( mode === "create") {
      setMode("empty");
    } else {
      setMode("display");
    }

    if(props.onComplete) {
      props.onComplete("cancel");
    }
  }

  return (
    <div className={"Observation" + mode}>
      <div className="ObservationHeader">
        <SpeciesName species={observation.species}></SpeciesName>
      </div>
      <div className="ObservationEditIcons">
        <IconButton onClick={(e) => doAccept()}>
          <CheckCircleOutline fontSize="large" />
        </IconButton>
        <div className="CountEntry">
          <div className="ObservationCount">{count}</div>
          <IconButton onClick={(e) => setCount(count - 1)} disabled={count <= 1}>
            <RemoveCircleOutlined fontSize="large" />
          </IconButton>
          <IconButton onClick={(e) => setCount(count +1)}>
            <AddCircleOutline fontSize="large" />
          </IconButton>
        </div>
        <div className="EntryControls">
          <MoreMenu doCancel={doCancel}></MoreMenu>
        </div>
      </div>
    </div>
  );
}
export default ObservationEntry;
export  {ObservationEntry, createObservation};
