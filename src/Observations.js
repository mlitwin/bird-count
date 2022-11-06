import Observation from './common/Observation';
import ListGroup from "react-bootstrap/ListGroup";
import { Virtuoso } from "react-virtuoso";

function Observations(props) {
  function observationContent(index) {
    const observation = props.observations[index];
    return (
      <ListGroup.Item key={observation.id}>
        <Observation observation={observation} />
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
