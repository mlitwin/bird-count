import React, { useRef, useState } from "react";
import FilterBar from "./FilterBar";
import Keyboard from "react-simple-keyboard";
import "react-simple-keyboard/build/css/index.css";
import "./Keypad.css";

function Keypad(props) {
  const [filter, setFilter] = useState("");
  const keyboard = useRef();
  const layout = {
    default: ["q w e r t y u i o p", "a s d f g h j k l", "z x c v b n m"],
  };

  const onChange = (input) => {
    setFilter(input);
    // console.log("Input changed", input);
  };

  return (
    <div className="Keypad">
       <FilterBar filter={filter} setFilter={setFilter} changeActive={props.changeActive} />
       <Keyboard
        keyboardRef={(r) => (keyboard.current = r)}
        onChange={onChange}
        layout={layout}
      />
    </div>
  );
}

export default Keypad;
