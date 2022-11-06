import { useSwipeable } from 'react-swipeable'
import Species from './Species'


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

    return (
        <span {...handlers} style={{ touchAction: 'pan-y' }}><Species species={species}></Species></span>
    )
}

export default Observation;