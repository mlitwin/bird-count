import { createRemoteJWKSet, jwtVerify } from "jose";

// Cognito M2M (client_credentials) access tokens do not include an `aud` claim.
// We distinguish token types by the presence of `aud`:
//   - User tokens:  aud present, must be in USER_AUDIENCES
//   - M2M tokens:   no aud, must carry the required scope in `scope`

const USER_POOL_ID = process.env.USER_POOL_ID!;
const ISSUER = `https://cognito-idp.${process.env.AWS_REGION}.amazonaws.com/${USER_POOL_ID}`;
const JWKS = createRemoteJWKSet(new URL(`${ISSUER}/.well-known/jwks.json`));
const USER_AUDIENCES = new Set(
  (process.env.USER_AUDIENCES ?? "").split(",").filter(Boolean)
);
const M2M_SCOPE = process.env.M2M_SCOPE!;

export async function handler(event: {
  headers?: Record<string, string>;
}): Promise<{ isAuthorized: boolean; context?: { sub: string } }> {
  const authHeader =
    event.headers?.authorization ?? event.headers?.Authorization ?? "";
  const token = authHeader.replace(/^Bearer /i, "");
  if (!token) return { isAuthorized: false };

  try {
    const { payload } = await jwtVerify(token, JWKS, { issuer: ISSUER });

    let sub: string | undefined;

    if (payload.aud !== undefined) {
      const auds = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
      if (!auds.some((a) => USER_AUDIENCES.has(a))) return { isAuthorized: false };
      sub = typeof payload.sub === "string" ? payload.sub : undefined;
    } else {
      const scopes =
        typeof payload.scope === "string" ? payload.scope.split(" ") : [];
      if (!scopes.includes(M2M_SCOPE)) return { isAuthorized: false };
      sub = typeof payload.sub === "string" ? payload.sub : undefined;
    }

    if (!sub) return { isAuthorized: false };
    return { isAuthorized: true, context: { sub } };
  } catch {
    return { isAuthorized: false };
  }
}
