import { useState } from 'react';
import {addObservation} from './store/store';
import Species from './common/Species';
import ListGroup from 'react-bootstrap/ListGroup';
import Button from 'react-bootstrap/Button';

function chooseObservation(species) {
   addObservation(species);
}

function SpeciesPicker(props) {

  const [active, setActive] = useState(0);

  const speciesList = props.species.map((species, index) => {
    const activeClass = index === active ? 'active' : '';
    return <ListGroup.Item key={species.id} className={activeClass} onClick={(e) => chooseObservation(species, e)}><Species species={species} /></ListGroup.Item>
  });
  return (
    <div className="speciesPicker">
        <ListGroup>
            {speciesList}
        </ListGroup>
    </div>
  );
}

export default SpeciesPicker;
