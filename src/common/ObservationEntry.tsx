import React from "react";
import Species from "./Species";
import MoreMenu from "./ObservationEntry/MoreMenu";
import { Observation } from "model/types";
import IconButton from "@mui/material/IconButton";
import {
  CheckCircleOutline,
  AddCircleOutline,
  RemoveCircleOutlined,
} from "@mui/icons-material";

import "./ObservationEntry.css";

interface ObservationProps {
  observation: Observation;
  initialMode: "display" | "edit";
}

function ObservationEntry(props: ObservationProps) {
  const observation = props.observation;

  if (!observation) {
    return <div className="ObservationSummary"></div>;
  }

  return (
    <div className="Observation">
      <div className="ObservationHeader">
        <Species species={observation.species}></Species>
      </div>
      <div className="ObservationEditIcons">
        <IconButton>
          <CheckCircleOutline fontSize="large" />
        </IconButton>
        <div className="CountEntry">
          <div className="ObservationCount">{observation.count}</div>
          <IconButton>
            <RemoveCircleOutlined fontSize="large" />
          </IconButton>
          <IconButton>
            <AddCircleOutline fontSize="large" />
          </IconButton>
        </div>
        <div className="EntryControls">
          <MoreMenu></MoreMenu>
        </div>
      </div>
    </div>
  );
}

export default ObservationEntry;
