import Species from "../common/Species";
import ListGroup from "react-bootstrap/ListGroup";
import React, { useRef, useEffect } from "react";
import { Virtuoso } from "react-virtuoso";

import "./SpeciesPicker.css";

function SpeciesPicker(props) {
  const virtuoso = useRef(null);


  useEffect(() => {
    if (virtuoso.current) {
      virtuoso.current.scrollIntoView({
        index: props.active,
        behavior: 'auto'
      });
    }
  });

  function itemContent(index) {
    const species = props.species[index];
    return (
      <ListGroup.Item
        key={species.id}
        onClick={(e) => props.chooseItem(index)}
        className={index === props.active ? "active" : ""}
      >
        <Species species={species} />
      </ListGroup.Item>
    );
  }

  return (
    <ListGroup className="SpeciesPicker">
      <Virtuoso
        ref={virtuoso}
        totalCount={props.species.length}
        itemContent={(index) => itemContent(index)}
      />
    </ListGroup>
  );
}

export default SpeciesPicker;
