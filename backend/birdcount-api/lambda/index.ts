import {
  Handler,
  APIGatewayProxyEventV2,
  APIGatewayProxyResultV2,
} from "aws-lambda";

import { createObservations } from "./dynamodb";

type ProxyHandler = Handler<APIGatewayProxyEventV2, APIGatewayProxyResultV2>;

async function addObservations(event, context) {
  const data = JSON.parse(event.body); // try/catch

  const observations = await createObservations(data.observations);

  return {
    statusCode: 200,
    body: JSON.stringify(observations),
  };
}

export const handler: ProxyHandler = async (event, context) => {
  switch (event.requestContext.http.method) {
    case "POST":
      return await addObservations(event, context);
    default:
      return {
        statusCode: 400,
        body: JSON.stringify({
          message: "Unsupported method",
        }),
      };
  }
};
