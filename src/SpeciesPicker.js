import {addObservation} from './store/store';
import Species from './common/Species';
import ListGroup from 'react-bootstrap/ListGroup';
import Button from 'react-bootstrap/Button';


function chooseObservation(species) {
   addObservation(species);
}

function SpeciesPicker(props) {
  const speciesList = props.species.map(species => 
    <ListGroup.Item key={species.code}><Species species={species} /> <Button onClick={(e) => chooseObservation(species, e)}>+</Button></ListGroup.Item>
  );
  return (
    <ListGroup>
        {speciesList}
    </ListGroup>
  );
}

export default SpeciesPicker;
