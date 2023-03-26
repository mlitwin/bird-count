import jose from 'node-jose';
import { SSMClient, GetParameterCommand} from "@aws-sdk/client-ssm";

const privateKeyPath = "/birdcount-api/dev/privateJWK"

const awsConfig = {
    region: "us-east-1"
}
const ssm_client = new SSMClient(awsConfig);



const ssm_command =  new GetParameterCommand({
    Name: "/birdcount-api/jwk",
    WithDecryption: true,
});

 const privateKeyResult = await ssm_client.send(ssm_command);
 const privateKeyStore = JSON.parse(privateKeyResult.Parameter.Value);

 const keystore = await jose.JWK.asKeyStore(privateKeyStore);

 const key = keystore.all().slice(-1)[0];
 const now =  Math.floor((new Date).getTime() / 1000);

 const claims = {
    iss: 'birdcount-api',
    iat: now,
    exp: now + 3600,
    sub: 'test'
  }

const payload = JSON.stringify(claims)
const opt = { compact: true, jwk: key, fields: { typ: 'jwt' } }
const token = await jose.JWS.createSign(opt, key)
                        .update(payload).final()

console.log(token);

const v = await jose.JWS.createVerify(keystore).verify(token)

console.log(v.header)
console.log(v.payload.toString())
  









