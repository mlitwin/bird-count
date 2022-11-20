import SpeciesName from "../common/SpeciesName";
import React, { useRef, useEffect } from "react";
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
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
      virtuoso.current.scrollToIndex({
        index: activeIndex,
        align: 'start',
        behavior: 'auto'
      });
    }
  });


  function itemContent(index) {
    const reveseIndex = virtuosoListIndex(index);
    const species = props.species[reveseIndex];
    return (
      <ListItem
        key={reveseIndex}
        onClick={(e) => props.chooseItem(reveseIndex)}
        className={reveseIndex === props.active ? "active" : ""}
      >
        <SpeciesName species={species} />
      </ListItem>
    );
  }

  const listKey = props.species.map((s,index) => s.id + index === activeIndex ? 'a': '').join('/');

  return (
    <List className="SpeciesPicker">
      <Virtuoso
        key={listKey}
        ref={virtuoso}
        totalCount={props.species.length}
        initialTopMostItemIndex={activeIndex}
        alignToBottom={true}
        itemContent={(index) => itemContent(index)}
      />
    </List>
  );
}

export default SpeciesPicker;
