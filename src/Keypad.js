import React, { useRef, useState } from "react";
import Button from "react-bootstrap/Button";
import ButtonGroup from "react-bootstrap/ButtonGroup";
import { propTypes } from "react-bootstrap/esm/Image";

import Keyboard from "react-simple-keyboard";
import "react-simple-keyboard/build/css/index.css";
import "./Keypad.css";

function Keypad(props) {
  const [input, setInput] = useState("");
  const keyboard = useRef();
  const layout = {
    default: ["q w e r t y u i o p", "a s d f g h j k l", "z x c v b n m"],
  };

  const onChange = (input) => {
    setInput(input);
    // console.log("Input changed", input);
  };

  const onChangeInput = (event) => {
    const input = event.target.value;
    setInput(input);
    keyboard.current.setInput(input);
  };

  function changeActiveSpecies(delta) {
    props.changeActive(delta);
  }

  return (
    <div className="Keypad">
      <div className="KeypadControls">
        <div className="KeyboadInputArea">
          <input
            value={input}
            placeholder={"Tap on the virtual keyboard to start"}
            onChange={onChangeInput}
          />
        </div>
        <ButtonGroup vertical>
          <Button>+</Button>
          <Button onClick={() => changeActiveSpecies(-1)}>↑</Button>
          <Button onClick={() => changeActiveSpecies(1)}>↓</Button>
        </ButtonGroup>
      </div>
      <Keyboard
        keyboardRef={(r) => (keyboard.current = r)}
        onChange={onChange}
        layout={layout}
      />
    </div>
  );
}

export default Keypad;
