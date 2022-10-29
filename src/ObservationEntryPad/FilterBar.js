import React, { useState } from "react";
import Button from "react-bootstrap/Button";
import ButtonGroup from "react-bootstrap/ButtonGroup";
import "./FilterBar.css";

function FilterBar(props) {
  function changeActiveSpecies(delta) {
    props.changeActive(delta);
  }

  const onChangeInput = (event) => {
    const input = event.target.value;
    props.setFilter(input);
  };

  return (
    <div className="KeypadControls">
      <div className="KeyboadInputArea">
        <input value={props.filter} onChange={onChangeInput} />
      </div>
      <div className="ListInteractionButtons">
        <ButtonGroup vertical>
          <Button>+</Button>
          <Button onClick={() => changeActiveSpecies(-1)}>↑</Button>
          <Button onClick={() => changeActiveSpecies(1)}>↓</Button>
        </ButtonGroup>
      </div>
    </div>
  );
}

export default FilterBar;
