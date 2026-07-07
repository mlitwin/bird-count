"use strict";

import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  PutCommand,
  QueryCommand,
} from "@aws-sdk/lib-dynamodb";

const table = process.env.DYNAMODB_TABLE as string;

const dynamodbClient = new DynamoDBClient({});
const ddbDocClient = DynamoDBDocumentClient.from(dynamodbClient);

function getTimestamp() {
  const now = new Date();
  return Math.round(now.getTime() / 1000);
}

function createObservationItem(obs) {
  return {
    compilation: obs.compilation,
    id: obs.id,
    createdAt: getTimestamp(),
    data: obs,
  };
}

async function createObservation(obs, statuses) {
  const obsItem = createObservationItem(obs);
  const params = {
    TableName: table,
    Item: obsItem,
    ConditionExpression: "attribute_not_exists(id)",
  };
  try {
    const data = await ddbDocClient.send(new PutCommand(params));
    statuses[obs.id] = {
      status: "success",
    };
  } catch (err) {
    statuses[obs.id] = {
      status: "failure",
      message: JSON.stringify(err),
    };
  }
}

async function createObservations(observations) {
  const statuses = {};

  observations.forEach((obs) => {
    statuses[obs.id] = {
      status: "unsent",
    };
  });

  for (let i = 0; i < observations.length; i++) {
    await createObservation(observations[i], statuses);
  }

  return { statuses };
}

async function queryObservations(compilation, createdAt) {
  let ret = {
    items: {},
    error: "",
  };
  const params = {
    TableName: table,
    IndexName: "createdAt",
    KeyConditionExpression: "compilation = :cp AND createdAt >= :ca",
    ExpressionAttributeValues: {
      ":cp": compilation,
      ":ca": createdAt,
    },
  };
  try {
    const data = await ddbDocClient.send(new QueryCommand(params));
    if (data?.Items) {
      ret.items = data.Items;
    }
  } catch (err) {
    ret.error = `error ${err} ${JSON.stringify(err)}`;
  }
  return ret;
}

export { createObservations, queryObservations };

/*

function backoff(attempt) {
  const cap = 10000;
  const base = 100;
  const sleep = Math.min(cap, base * (2 ** attempt));
  const ms = Math.random() * sleep;
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}


async function addObservations(event, context) {
  const data = JSON.parse(event.body); // try/catch

  const [items, error] = createObservations(data.observations);

  if (error) {
    return {
      statusCode: 400,
      headers: { "Content-Type": "text/plain" },
      body: error,
    };
  }

  const table = process.env.DYNAMODB_TABLE as string;

  let params: any = {
    RequestItems: {},
  };

  const requests = items.map((i) => ({
    PutRequest: {
      Item: i,
    },
  }));

  params.RequestItems[table] = requests;
  const querykey = new Date();

  let tries = 0;
  while (Object.keys(params).length > 0 && tries < 8) {
    // TBD exponential backoff starting at 0

    if( tries > 0) {
      await backoff(tries);
    }
    params.RequestItems[table].forEach((item) => {
      item.PutRequest.Item.ksuid = KSUID.randomSync().string;
    });

    const command = new BatchWriteCommand(params);
    const result = await dynamodb.send(command);
    params = result.UnprocessedItems;
    tries++;
  }

  querykey.setTime(querykey.getTime() - 1000 * 60 * 5);

  const queryToken = KSUID.randomSync(querykey).string;
  const ret = {
    queryToken,
    observations: items,
  };

  return {
    statusCode: 200,
    body: JSON.stringify(ret),
  };
}*/
