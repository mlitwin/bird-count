import { addObservation } from "../store/store";
import Species from "../common/Species";
import ListGroup from "react-bootstrap/ListGroup";
import React, { useRef, useEffect } from "react";
import scrollIntoView from "scroll-into-view-if-needed";

import "./SpeciesPicker.css";

function chooseObservation(species) {
  addObservation(species);
}

function SpeciesPicker(props) {
  const activeRef = useRef();

  useEffect(() => {
    if (activeRef.current) {
      scrollIntoView(activeRef.current, {
        scrollMode: "if-needed",
        block: "nearest",
        inline: "nearest",
      });
    }
  });

  const speciesList = props.species.map((species, index) => {
    if (index === props.active) {
      return (
        <ListGroup.Item
          ref={activeRef}
          key={species.id}
          className="active"
          onClick={(e) => chooseObservation(species, e)}
        >
          <Species species={species} />
        </ListGroup.Item>
      );
    }
    return (
      <ListGroup.Item
        key={species.id}
        onClick={(e) => chooseObservation(species, e)}
      >
        <Species species={species} />
      </ListGroup.Item>
    );
  });
  return (
    <div className="speciesPicker">
      <ListGroup>{speciesList}</ListGroup>
    </div>
  );
}

export default SpeciesPicker;