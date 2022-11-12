import ObservationEntry from './common/ObservationEntry';
import ListGroup from "react-bootstrap/ListGroup";
import { Virtuoso } from "react-virtuoso";

function Observations(props) {
  function observationContent(index) {
    const observation = props.observations[index];
    return (
      <ListGroup.Item key={observation.id}>
        <ObservationEntry observation={observation} />
      </ListGroup.Item>
    );
  }

  return (
    <ListGroup className="oneColumnExpand">
      <Virtuoso
        totalCount={props.observations.length}
        itemContent={(index) => observationContent(index)}
      />
    </ListGroup>
  );
}

export default Observations;
