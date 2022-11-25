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

import { addObservation } from "../store/store";

import { v4 as uuidv4 } from "uuid";

import "./ObservationEntry.css";

type Modes = "empty" | "display" | "edit" | "create";

interface IObservationEntryEvent {
  type: "accept" | "cancel";
  observation: Observation | null;
}

interface ObservationProps {
  initialMode: Modes;
  observation: Observation | Species;
  onEvent?: (event: IObservationEntryEvent) => void;
}

function createObservation(species: Species): Observation {
  const now = Date.now();
  const observation = {
    id: uuidv4(),
    createdAt: now,
    start: now,
    duration: 0,
    species,
    count: 1,
    parent: null,
  };

  return observation;
}

function createChildObservation(
  parent: Observation,
  count: number
): Observation {
  const now = Date.now();
  const observation = {
    id: uuidv4(),
    createdAt: now,
    start: now,
    duration: 0,
    species: parent.species,
    count: count,
    parent: parent,
  };

  return observation;
}

function ObservationEntry(props: ObservationProps) {
  const [observation, setObservation] = useState<Observation | null>(
    props.observation
  );
  const [mode, setMode] = useState<Modes>(props.initialMode);
  const currentCount = observation ? observation.count : 0;
  const [count, setCount] = useState(currentCount);

  if (mode === "empty" || !observation) {
    return <div className="ObservationSummary placeholder"></div>;
  }

  if (mode === "display") {
    return (
      <div className="Observation display" onClick={onClick}>
        <div className="ObservationHeader">
          <div className="ObservationCount">{observation.count}</div>
          <SpeciesName species={observation.species}></SpeciesName>
        </div>
      </div>
    );
  }

  function doAccept() {
    if (mode === "create") {
      observation.count = count;
      addObservation(observation);
    } else {
      const delta = count - observation.count;
      const child = createChildObservation(observation, delta);
      addObservation(child);
    }
    setMode("display");

    if (props.onEvent) {
      props.onEvent({
        type: "accept",
        observation,
      });
    }
  }

  function doCancel() {
    if (mode === "create") {
      setMode("empty");
      setObservation(null);
    } else {
      setMode("display");
    }

    if (props.onEvent) {
      props.onEvent({
        type: "cancel",
        observation,
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
        <SpeciesName species={observation.species}></SpeciesName>
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
