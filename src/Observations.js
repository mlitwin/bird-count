import ListGroup from "react-bootstrap/ListGroup";

function Observations(props) {
  const observations = props.observations.map((observation) => (
    <ListGroup.Item key={observation.id}>
      {observation.species.name}
    </ListGroup.Item>
  ));
  return <ListGroup className="oneColumnExpand">{observations}</ListGroup>;
}

export default Observations;
