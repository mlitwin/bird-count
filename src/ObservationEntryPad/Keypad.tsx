import React, { useRef } from "react";
import Keyboard from "react-simple-keyboard";
import "react-simple-keyboard/build/css/index.css";
import "./Keypad.css";

function Keypad(props) {
  const keyboard = useRef();
  const layout = {
    default: ["Q W E R T Y U I O P", "A S D F G H J K L", "Z X C V B N M"],
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
