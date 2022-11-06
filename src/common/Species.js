import { useSwipeable } from 'react-swipeable'


function Species(props) {
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
    
    const species = props.species;
    const speciesName = species ? species.localizations.en.commonName : '';

    return (
        <span {...handlers} style={{ touchAction: 'pan-y' }}>{speciesName}</span>
    )
}

export default Species;