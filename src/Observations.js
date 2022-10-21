
function Observations(props) {
    const observations = props.observations.map(observation => 
      <li key={observation.createdAt}>{observation.species.name}</li>
    );
    return (
      <ul className="Observations">
          {observations}
      </ul>
    );
  }
  
  export default Observations;
  