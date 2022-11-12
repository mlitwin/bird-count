import React from "react";
import { ButtonGroup } from "react-bootstrap";
import Button from "react-bootstrap/Button";
import "./FilterBar.css";

function FilterBar(props) {
  function doBack() {
    props.setFilter(props.filter.substring(0, props.filter.length - 1));
  }

  function doClear() {
    props.setFilter("");
  }

  return (
    <div className="KeypadControls">
      <Button className="enter" onClick={(e) => props.chooseItem()}>ENTER</Button>
      <div className="FilterValue">&#8203;{props.filter}</div>
      <ButtonGroup className="FilterControls">
        <Button onClick={(e) => doBack()}>BSP</Button>
        <Button onClick={(e) => doClear()}>CLEAR</Button>
      </ButtonGroup>
    </div>
  );
}

export default FilterBar;
