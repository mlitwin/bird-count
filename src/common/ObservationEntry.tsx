import React, { useState } from "react";
import SpeciesName from "./SpeciesName";
import MoreMenu from "./ObservationEntry/MoreMenu";
import { Observation, Species } from "model/types";
import IconButton from "@mui/material/IconButton";
import {
  CheckCircleOutline,
  AddCircleOutline,
  RemoveCircleOutlined,
} from "@mui/icons-material";

import { observations, addObservation, useObservationQuery } from "../store/store";

import { v4 as uuidv4 } from "uuid";

import "./ObservationEntry.css";

type Modes = "display" | "edit" | "create" ;

interface IObservationEntryEvent {
  type: "accept" | "cancel";
  observation: Observation;
}

interface ObservationProps {
  initialMode: Modes;
  observation: Observation;
  onEvent?: (event: IObservationEntryEvent) => void;
}

function createObservation(species: Species): Observation {
  const now = Date.now();
  let obs = new Observation();

  obs.id = uuidv4();
  obs.createdAt= now;
  obs.start = now;
  obs.duration = 0
  obs.species = species;
  obs.count = 1
  obs.parent = null
  

  return obs;
}

function createChildObservation(
  parent: Observation,
  count: number
): Observation {
  const now = Date.now();
  let obs = new Observation();

  obs.id = uuidv4();
  obs.createdAt= now;
  obs.start = now;
  obs.duration = 0
  obs.species = parent.species;
  obs.count = count;
  obs.parent = parent

  return obs;
}

function ObservationEntry(props: ObservationProps) {

  const [mode, setMode] = useState<Modes>(props.initialMode);

  const curObservations = observations();

  const query = useObservationQuery((obs)=> {
    if (obs.id === props.observation.id ) return true;

    if( obs.parent && obs.parent.id === props.observation.id) return true;

    return false;
  });

  const [count, setCount] = useState(props.observation.count);

  if (mode === "display") {
    return (
      <div className="Observation display" onClick={onClick}>
        <div className="ObservationHeader">
          <div className="ObservationCount">{query.count}</div>
          <SpeciesName species={query.species}></SpeciesName>
        </div>
      </div>
    );
  }

  function doAccept() {
    if (mode === "create") {
      props.observation.count = count;
      addObservation(curObservations, props.observation);
    } else {
      const delta = count - query.count;
      const child = createChildObservation(props.observation, delta);
      addObservation(curObservations, child);
    }
    setMode("display");

    if (props.onEvent) {
      props.onEvent({
        type: "accept",
        observation: props.observation,
      });
    }
  }

  function doCancel() {

    setMode("display");

    if (props.onEvent) {
      props.onEvent({
        type: "cancel",
        observation: props.observation,
      });
    }
  }

  function onClick() {
    if (mode === "display") {
      setMode("edit");
    }
  }


  return (
    <div className={"Observation " + mode}>
      <div className="ObservationHeader">
        <SpeciesName species={query.species}></SpeciesName>
      </div>
      <div className="ObservationEditIcons">
        <div className="EntryControls">
          <MoreMenu doCancel={doCancel}></MoreMenu>
        </div>
        <div className="CountEntry">
          <div className="ObservationCount">{count}</div>
          <IconButton
            onClick={(e) => setCount(count - 1)}
            disabled={count <= 1}
          >
            <RemoveCircleOutlined fontSize="large" />
          </IconButton>
          <IconButton onClick={(e) => setCount(count + 1)}>
            <AddCircleOutline fontSize="large" />
          </IconButton>
        </div>
        <IconButton onClick={(e) => doAccept()}>
          <CheckCircleOutline fontSize="large" />
        </IconButton>
      </div>
    </div>
  );
}
export default ObservationEntry;
export { ObservationEntry, createObservation };
