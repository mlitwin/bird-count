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
      <div className="FilterValue"><div>{props.filter}</div></div>
      <ButtonGroup variant="contained" className="FilterControls">
        <Button onClick={(e) => doBack()}>BSP</Button>
        <Button onClick={(e) => doClear()}>CLEAR</Button>
      </ButtonGroup>
    </div>
  );
}

export default FilterBar;
