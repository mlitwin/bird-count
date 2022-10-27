import ListGroup from "react-bootstrap/ListGroup";

function Observations(props) {
  const observations = props.observations.map((observation) => (
    <ListGroup.Item key={observation.createdAt}>
      {observation.species.name}
    </ListGroup.Item>
  ));
  return <ListGroup>{observations}</ListGroup>;
}

export default Observations;
