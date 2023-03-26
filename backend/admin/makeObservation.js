import axios from 'axios';
import * as uuid  from 'uuid';

function makeObservation() {
    const id = uuid.v4()

    return {
        id,
        user: 'user',
        group: 'group',
        start: 0,
        duration: 0,
        location_latitude: 0,
        location_longitude: 0,
        taxonomy: 'taxonomy',
        species: 'species',
        count: 1,
        parent: '',
    }
}

const obs = [makeObservation()]

const url = "https://0lb8bg47b9.execute-api.us-east-1.amazonaws.com/dev";
const JWT = process.env.JWT;

const config = {
    headers: {
      Authorization: `Bearer ${JWT}`
    }
  }

axios
    .post(url, {
        observations: obs
    }, config)
    .then(function (response) {
        console.log(response.data)
    })
    .catch(function (error) {
        console.log(error)
    })
