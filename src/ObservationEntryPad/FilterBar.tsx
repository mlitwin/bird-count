import React from "react";
import Button from '@mui/material/Button';
import ButtonGroup from '@mui/material/ButtonGroup';
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
      <Button variant="contained" className="enter" onClick={(e) => props.chooseItem()}>ENTER</Button>
      <div className="FilterValue">&#8203;{props.filter}</div>
      <ButtonGroup variant="contained" className="FilterControls">
        <Button onClick={(e) => doBack()}>BSP</Button>
        <Button onClick={(e) => doClear()}>CLEAR</Button>
      </ButtonGroup>
    </div>
  );
}

export default FilterBar;
