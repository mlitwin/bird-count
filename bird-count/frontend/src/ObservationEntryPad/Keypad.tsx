import React, { useRef } from 'react'
import Keyboard from 'react-simple-keyboard'
import 'react-simple-keyboard/build/css/index.css'
import './Keypad.css'

const bsp = '␈'
const clr = '✕'

function Keypad(props) {
    const keyboard = useRef()
    const layout = {
        default: [
            'Q W E R T Y U I O P',
            'A S D F G H J K L',
            `Z X C V B N M ${bsp} ${clr}`,
        ],
    }

    const onKeyPress = (k) => {
        let newFilter = { ...props.filter }
        switch (k) {
            case bsp:
                newFilter.text = newFilter.text.slice(0, -1)
                break
            case clr:
                newFilter.text = ''
                break
            default:
                newFilter.text += k
        }
        props.setFilter(newFilter)
    }

    return (
        <div className="Keypad">
            <Keyboard
                keyboardRef={(r) => (keyboard.current = r)}
                onKeyPress={onKeyPress}
                layout={layout}
                buttonAttributes={[
                    {
                        attribute: 'data-type',
                        value: 'control',
                        buttons: `${bsp} ${clr}`,
                    },
                ]}
            />
        </div>
    )
}

export default Keypad
