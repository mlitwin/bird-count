import { Button} from "react-bootstrap";

import Observations from "./Observations";
import { observations } from "./store/store";

function ObservationHistory() {
  const obs = observations();

  function doClear() {}
  return (
    <div className="oneColumn">
      <Observations observations={obs} />
      <Button onClick={(e) => doClear()}>CLEAR</Button>
    </div>
  );
}

export default ObservationHistory;
