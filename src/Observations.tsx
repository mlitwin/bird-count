import ObservationEntry from "./common/ObservationEntry";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import { Virtuoso } from "react-virtuoso";
import * as React from "react";
import "./Observations.css";

function Observations(props) {
  function observationContent(index) {
    const observation = props.observations[index];
    return (
      <ListItem>
        <ObservationEntry observation={observation} />
      </ListItem>
    );
  }

  return (
    <div className="oneColumnExpand">
      <List className="Observations">
        <Virtuoso
          totalCount={props.observations.length}
          itemContent={(index) => observationContent(index)}
        />
      </List>
    </div>
  );
}

export default Observations;
