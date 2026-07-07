import jose from 'node-jose';
import { SSMClient, GetParameterCommand, PutParameterCommand} from "@aws-sdk/client-ssm";
import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";

const awsConfig = {
    region: "us-east-1"
}
const ssm_client = new SSMClient(awsConfig);
const s3_client = new S3Client(awsConfig);

const now = new Date();

function pruneKeys(jwks, now, ageLimit) {
    let keysToKeep = [];
    jwks.keys.forEach(k => {
        const createdAt = jwks.keyCreationTime[k];
        if(createdAt !== undefined && (now - createdAt) < ageLimit) {
            keysToKeep.push(jwks.keys[k]);
        } else {
            delete jwks.keyCreationTime[k];
        }
    });
        
    jwks.keys = keysToKeep;
}


let existingJWKS = { keyCreationTime: {},
    keys: []
};

try {
    const ssm_get_command =  new GetParameterCommand({
        Name: "/birdcount-api/jwk",
        WithDecryption: true,
    });

    const existingJWKSResponse = await ssm_client.send(ssm_get_command);

    existingJWKS = JSON.parse(await existingJWKSResponse.Value);
} catch(e) {

}

pruneKeys(existingJWKS, now, 24*60*60);

const keystore = await jose.JWK.asKeyStore(existingJWKS);

const newKey = await keystore.generate("RSA", 2048);

const privateKeyStore = keystore.toJSON(true);
const publicKeyStore = keystore.toJSON();

privateKeyStore.keyCreationTime = {};
Object.assign(privateKeyStore.keyCreationTime, existingJWKS.keyCreationTime);
privateKeyStore.keyCreationTime[newKey.kid] = now.toISOString();


const s3_command = new PutObjectCommand({
    Bucket: "birdcount-api-storage",
    Key: "/birdcount-api/jwks.json",
    Body: JSON.stringify(publicKeyStore)
  });

const ssm_command =  new PutParameterCommand({
    Name: "/birdcount-api/jwk",
    Value: JSON.stringify(privateKeyStore),
    Overwrite: true,
    Type: "SecureString"
});


 await s3_client.send(s3_command);
 await ssm_client.send(ssm_command);

 console.log(privateKeyStore);
 console.log(publicKeyStore);






