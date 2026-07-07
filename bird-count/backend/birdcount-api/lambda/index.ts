import {
  Handler,
  APIGatewayProxyEventV2,
  APIGatewayProxyResultV2,
} from "aws-lambda";

import { createObservations, queryObservations } from "./dynamodb";

type ProxyHandler = Handler<APIGatewayProxyEventV2, APIGatewayProxyResultV2>;

async function addObservations(event, context) {
  const data = JSON.parse(event.body); // try/catch

  const observations = await createObservations(data.observations);

  return {
    statusCode: 200,
    body: JSON.stringify(observations),
  };
}

async function query(event, context) {
  const data = JSON.parse(event.body); // try/catch

  const compilation = data.compilation;
  const createdAt = data.createdAt || 0;

  const observations = await queryObservations(compilation, createdAt);

  return {
    statusCode: 200,
    body: JSON.stringify(observations),
  };
}

export const handler: ProxyHandler = async (event, context) => {
  const method = event.requestContext.http.method;
  const path = event.requestContext.http.path.replace(/^\/[^/]*\//, "/");

  if (method === "POST" && path === "/observations") {
    return await addObservations(event, context);
  }

  if (method === "POST" && path === "/observations/query") {
    return await query(event, context);
  }

  return {
    statusCode: 400,
    body: JSON.stringify({
      message: `Unsupported: ${method} ${path}`,
    }),
  };
};
