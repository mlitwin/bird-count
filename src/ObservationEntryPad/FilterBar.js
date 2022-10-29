import React from "react";
import { ButtonGroup } from "react-bootstrap";
import Button from "react-bootstrap/Button";
import "./FilterBar.css";

function FilterBar(props) {
  return (
    <div className="KeypadControls">
      <Button>ENTER</Button>
      <div className="FilterValue">&#8203;{props.filter}</div>
      <ButtonGroup className="FilterControls">
        <Button>BSP</Button>
        <Button>CLEAR</Button>
      </ButtonGroup>
    </div>
  );
}

export default FilterBar;
