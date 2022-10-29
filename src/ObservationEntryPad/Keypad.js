import React, { useRef } from "react";
import Keyboard from "react-simple-keyboard";
import "react-simple-keyboard/build/css/index.css";
import "./Keypad.css";

function Keypad(props) {
  const keyboard = useRef();
  const layout = {
    default: ["q w e r t y u i o p", "a s d f g h j k l", "z x c v b n m"],
  };

  const onKeyPress = (k) => {
    props.setFilter(props.filter + k);
  };

  return (
    <div className="Keypad">
       <Keyboard
        keyboardRef={(r) => (keyboard.current = r)}
        onKeyPress={onKeyPress}
        layout={layout}
      />
    </div>
  );
}

export default Keypad;
