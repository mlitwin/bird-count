import React from "react";
import Button from "react-bootstrap/Button";
import ButtonGroup from "react-bootstrap/ButtonGroup";
import "./SpeciesNavigation.css";

function SpeciesNavigation(props) {
  function changeActiveSpecies(delta) {
    props.changeActive(delta);
  }

  return (
    <div className="SpeciesNavigation">
      <ButtonGroup vertical>
        <Button onClick={() => changeActiveSpecies(-1)}>↑</Button>
        <Button onClick={() => changeActiveSpecies(1)}>↓</Button>
      </ButtonGroup>
    </div>
  );
}

export default SpeciesNavigation;
