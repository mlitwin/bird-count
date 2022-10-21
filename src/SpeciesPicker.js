import {addObservation} from './store/store';

function chooseObservation(species) {
   // console.log(species);
   addObservation(species);
}

function SpeciesPicker(props) {
  const species = props.species.map(species => 
    <li key={species.code}>{species.name} <button onClick={(e) => chooseObservation(species, e)}>+</button></li>
  );
  return (
    <ul className="SpeciesPicker">
        {species}
    </ul>
  );
}

export default SpeciesPicker;
