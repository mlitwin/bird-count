import { vi, describe, it, expect, beforeAll, beforeEach } from "vitest";

vi.mock("jose", () => ({
  createRemoteJWKSet: vi.fn(() => "mock-jwks"),
  jwtVerify: vi.fn(),
}));

import { jwtVerify } from "jose";

const mockVerify = jwtVerify as ReturnType<typeof vi.fn>;

let handler: (event: { headers?: Record<string, string> }) => Promise<{
  isAuthorized: boolean;
  context?: { sub: string };
}>;

const IOS_CLIENT = "ios-client-id";
const WEB_CLIENT = "web-client-id";
const M2M_SCOPE = "https://api.internal/sync";

beforeAll(async () => {
  process.env.USER_POOL_ID = "us-east-1_TEST123";
  process.env.AWS_REGION = "us-east-1";
  process.env.USER_AUDIENCES = `${IOS_CLIENT},${WEB_CLIENT}`;
  process.env.M2M_SCOPE = M2M_SCOPE;
  ({ handler } = await import("../src/authorizer.js"));
});

beforeEach(() => {
  vi.clearAllMocks();
});

describe("authorizer - missing / malformed token", () => {
  it("denies missing Authorization header", async () => {
    const r = await handler({ headers: {} });
    expect(r.isAuthorized).toBe(false);
  });

  it("denies empty Bearer token", async () => {
    const r = await handler({ headers: { Authorization: "Bearer " } });
    expect(r.isAuthorized).toBe(false);
  });

  it("denies when jwtVerify throws (invalid signature)", async () => {
    mockVerify.mockRejectedValue(new Error("JWTInvalid"));
    const r = await handler({ headers: { Authorization: "Bearer bad.token.here" } });
    expect(r.isAuthorized).toBe(false);
  });
});

describe("authorizer - Cognito user access token (client_id path)", () => {
  it("allows token with known client_id and sub", async () => {
    mockVerify.mockResolvedValue({ payload: { sub: "user-uuid", client_id: IOS_CLIENT } });
    const r = await handler({ headers: { Authorization: "Bearer valid.access.token" } });
    expect(r.isAuthorized).toBe(true);
    expect(r.context?.sub).toBe("user-uuid");
  });

  it("allows web client_id", async () => {
    mockVerify.mockResolvedValue({ payload: { sub: "user-uuid", client_id: WEB_CLIENT } });
    const r = await handler({ headers: { Authorization: "Bearer valid.access.token" } });
    expect(r.isAuthorized).toBe(true);
  });

  it("denies token with unknown client_id", async () => {
    mockVerify.mockResolvedValue({ payload: { sub: "user-uuid", client_id: "unknown-app" } });
    const r = await handler({ headers: { Authorization: "Bearer valid.access.token" } });
    expect(r.isAuthorized).toBe(false);
  });

  it("denies access token with no sub", async () => {
    mockVerify.mockResolvedValue({ payload: { client_id: IOS_CLIENT } });
    const r = await handler({ headers: { Authorization: "Bearer no-sub.token" } });
    expect(r.isAuthorized).toBe(false);
  });

  it("handles lowercase authorization header", async () => {
    mockVerify.mockResolvedValue({ payload: { sub: "user-uuid", client_id: IOS_CLIENT } });
    const r = await handler({ headers: { authorization: "Bearer valid.access.token" } });
    expect(r.isAuthorized).toBe(true);
  });
});

describe("authorizer - Cognito ID token (aud path)", () => {
  it("allows ID token with matching aud", async () => {
    mockVerify.mockResolvedValue({ payload: { sub: "user-uuid", aud: IOS_CLIENT } });
    const r = await handler({ headers: { Authorization: "Bearer valid.id.token" } });
    expect(r.isAuthorized).toBe(true);
    expect(r.context?.sub).toBe("user-uuid");
  });

  it("allows ID token with aud as array", async () => {
    mockVerify.mockResolvedValue({ payload: { sub: "user-uuid", aud: [IOS_CLIENT, "other"] } });
    const r = await handler({ headers: { Authorization: "Bearer valid.id.token" } });
    expect(r.isAuthorized).toBe(true);
  });

  it("denies ID token with wrong aud", async () => {
    mockVerify.mockResolvedValue({ payload: { sub: "user-uuid", aud: "wrong-app" } });
    const r = await handler({ headers: { Authorization: "Bearer valid.id.token" } });
    expect(r.isAuthorized).toBe(false);
  });
});

describe("authorizer - M2M token (scope path)", () => {
  it("allows M2M token with required scope", async () => {
    mockVerify.mockResolvedValue({
      payload: { sub: "m2m-client", scope: `other-scope ${M2M_SCOPE}` },
    });
    const r = await handler({ headers: { Authorization: "Bearer valid.m2m.token" } });
    expect(r.isAuthorized).toBe(true);
    expect(r.context?.sub).toBe("m2m-client");
  });

  it("denies M2M token missing required scope", async () => {
    mockVerify.mockResolvedValue({ payload: { sub: "m2m-client", scope: "other-scope" } });
    const r = await handler({ headers: { Authorization: "Bearer valid.m2m.token" } });
    expect(r.isAuthorized).toBe(false);
  });

  it("denies M2M token with no sub", async () => {
    mockVerify.mockResolvedValue({ payload: { scope: M2M_SCOPE } });
    const r = await handler({ headers: { Authorization: "Bearer m2m-no-sub.token" } });
    expect(r.isAuthorized).toBe(false);
  });
});
