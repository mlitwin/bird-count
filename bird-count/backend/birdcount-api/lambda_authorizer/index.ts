import {
  APIGatewayRequestSimpleAuthorizerHandlerV2,
  APIGatewayRequestAuthorizerEventV2,
} from "aws-lambda";

import authenticator from "./authenticator";

const awsConfig = {
  region: "us-east-1",
};

const authenticate = authenticator(awsConfig);

export const handler: APIGatewayRequestSimpleAuthorizerHandlerV2 = async (
  event: APIGatewayRequestAuthorizerEventV2
) => {



  const authHeader = event?.headers?.authorization;
  if (!authHeader) {
    return {
      isAuthorized: false,
      context: {
        message: "noHeader"
      }
    };
  }

  const token = authHeader.replace(/^Bearer\s+/, "");

  try {
    const authorized = await authenticate(token);
    return {
      isAuthorized: true,
    };
  } catch (e) {
    return {
      isAuthorized: false,
      context: {
        message: "failed"
      }
    };
  }
};
