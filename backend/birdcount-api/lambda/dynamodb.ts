"use strict";

import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  PutCommand,
  UpdateCommand,
} from "@aws-sdk/lib-dynamodb";

const table = process.env.DYNAMODB_TABLE as string;

const dynamodbClient = new DynamoDBClient({});
const ddbDocClient = DynamoDBDocumentClient.from(dynamodbClient);

function createObservationItem(obs, querykey) {
  return {
    querykey: querykey,
    compilation: obs.compilation,
    id: obs.id,
    data: obs,
  };
}

async function createObservation(obs, querykey, statuses) {
  const obsItem = createObservationItem(obs, querykey);
  const params = {
    TableName: table,
    Item: obsItem,
    ConditionExpression: "attribute_not_exists(id)",
  };
  try {
    const data = await ddbDocClient.send(new PutCommand(params));
    statuses[obs.id] = {
      status: "success",
      querykey: obsItem.querykey,
    };
  } catch (err) {
    statuses[obs.id] = {
      status: "failure",
      message: JSON.stringify(err),
    };
  }
}

async function getquerykey(increment) {
  const params = {
    TableName: table,
    Key: { compilation: "_gloablquerykey", id: "querykey" },
    UpdateExpression: "SET querykey = if_not_exists(querykey, :start) + :inc",
    ExpressionAttributeValues: { ":start": 0, ":inc": 1 },
    ReturnValues: "UPDATED_NEW",
  };
  const data = await ddbDocClient.send(new UpdateCommand(params));
  if (!data.Attributes) {
    throw `bad getquerykey return ${JSON.stringify(data)}`;
  }
  return data.Attributes["querykey"] - increment;
}

async function createObservations(observations) {
  const statuses = {};
  const querykey = await getquerykey(observations.length);

  observations.forEach((obs) => {
    statuses[obs.id] = {
      status: "unsent",
    };
  });

  for (let i = 0; i < observations.length; i++) {
    await createObservation(observations[i], querykey + i, statuses);
  }

  return { statuses, querykey };
}

export { createObservations };

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
