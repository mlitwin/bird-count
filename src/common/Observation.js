import { useSwipeable } from 'react-swipeable'
import Species from './Species'

import "./Observation.css";


function Observation(props) {
    const config = {
        trackMouse: true,
        preventScrollOnSwipe: true
    };

    const handlers = useSwipeable({
        onSwiped: (eventData) => console.log("onSwiped", eventData),
        onSwipeStart: (eventData) => console.log("onSwipeStart", eventData),
        onSwiping: (eventData) => console.log("onSwiping", eventData),
        ...config,
      });
    
    const species = props.observation ? props.observation.species: null;
    const speciesHTML = (
        <Species species={species}></Species>
    );

    return (
        <span className='Observation' {...handlers} style={{ touchAction: 'pan-y' }}>{speciesHTML}</span>
    )
}

export default Observation;