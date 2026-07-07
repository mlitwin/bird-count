import axios from 'axios';


const compilation = 'compilation';
const createdAt = 0;
const url = "https://0lb8bg47b9.execute-api.us-east-1.amazonaws.com/dev/observations/query";
const JWT = process.env.JWT;

const config = {
    headers: {
      Authorization: `Bearer ${JWT}`
    }
  }

axios
    .post(url, {
        compilation,
        createdAt
    }, config)
    .then(function (response) {
        console.log(response.data)
    })
    .catch(function (error) {
        console.log(error)
    })
