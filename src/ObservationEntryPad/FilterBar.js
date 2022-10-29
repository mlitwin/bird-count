import React from "react";
import Button from "react-bootstrap/Button";
import "./FilterBar.css";

function FilterBar(props) {

  return (
    <div className="KeypadControls">
      <div className="KeyboadInputArea">
      <Button>+</Button>
      <div>&#8203;{props.filter}</div>
      </div>
    </div>
  );
}

export default FilterBar;
