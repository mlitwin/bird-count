import Observations from './Observations';
import {observations} from './store/store'

function ObservationHistory() {

  const obs = observations();
  return (
      <Observations observations={obs} />
  );
}

export default ObservationHistory;
