"use strict";

import jwksClient from "jwks-rsa";
import jsonwebtoken from "jsonwebtoken";
import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";

function authenticator(awsConfig) {
  const s3_client = new S3Client(awsConfig);

  const jwksUrl =
    "https://birdcount-api-storage.s3.amazonaws.com/birdcount-api/jwks.json";

  const jwks = jwksClient({
    jwksUri: jwksUrl,

    fetcher: async (jwksUri: string): Promise<{ keys: any }> => {
      let ret = { keys: [] };

      const s3_command = new GetObjectCommand({
        Bucket: "birdcount-api-storage",
        Key: "/birdcount-api/jwks.json",
      });

      const response = await s3_client.send(s3_command);
      if (response.Body) {
        const str = await response.Body.transformToString();
        ret = JSON.parse(str);
      }

      return ret;
    },
  });

  return async (jwt: string) => {
    const decoded = jsonwebtoken.decode(jwt, { complete: true });
    if (!decoded) {
      throw new Error("Invalid JWT");
    }
    const kid = decoded.header.kid;
    const key = await jwks.getSigningKey(kid);
    const signingKey = key.getPublicKey();
    const verified = jsonwebtoken.verify(jwt, signingKey);
    return verified;
  };
}

export default authenticator;
