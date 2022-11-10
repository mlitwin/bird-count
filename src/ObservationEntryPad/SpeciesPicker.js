import Species from "../common/Species";
import ListGroup from "react-bootstrap/ListGroup";
import React, { useRef, useEffect } from "react";
import { Virtuoso } from "react-virtuoso";

import "./SpeciesPicker.css";

function SpeciesPicker(props) {
  const virtuoso = useRef(null);

  function virtuosoListIndex(index) {
    return props.species.length - index - 1;
  }

  const activeIndex = virtuosoListIndex(props.active);



  useEffect(() => {
    if (virtuoso.current) {
      virtuoso.current.scrollIntoView({
        index: activeIndex,
        behavior: 'auto'
      });
    }
  });


  function itemContent(index) {
    const reveseIndex = virtuosoListIndex(index);
    const species = props.species[reveseIndex];
    return (
      <ListGroup.Item
        key={reveseIndex}
        onClick={(e) => props.chooseItem(reveseIndex)}
        className={reveseIndex === props.active ? "active" : ""}
      >
        <Species species={species} />
      </ListGroup.Item>
    );
  }

  const listKey = props.species.map((s,index) => s.id + index === activeIndex ? 'a': '').join('/');

  return (
    <ListGroup className="SpeciesPicker">
      <Virtuoso
        key={listKey}
        ref={virtuoso}
        totalCount={props.species.length}
        initialTopMostItemIndex={activeIndex}
        alignToBottom={true}
        itemContent={(index) => itemContent(index)}
      />
    </ListGroup>
  );
}

export default SpeciesPicker;
