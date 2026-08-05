import Redis from "ioredis";

let _client: Redis | undefined;

export function valkeyClient(): Redis {
  if (!_client) {
    const endpoint = process.env.VALKEY_ENDPOINT;
    if (!endpoint) throw new Error("VALKEY_ENDPOINT is not set");
    _client = new Redis(endpoint, { tls: {}, lazyConnect: false, maxRetriesPerRequest: 3 });
  }
  return _client;
}

export function tripSeqKey(trip: string): string {
  return `trip:${trip}:seq`;
}

// Increments key only if it already exists. Returns new value, or -1 if key is absent.
const LUA_INCR_IF_EXISTS = `
  if redis.call('EXISTS', KEYS[1]) == 1 then
    return redis.call('INCR', KEYS[1])
  else
    return -1
  end`;

export async function guardedIncr(client: Redis, key: string): Promise<number> {
  return client.eval(LUA_INCR_IF_EXISTS, 1, key) as Promise<number>;
}

// Sets key to value only when value > current (raise-only). Returns true if SET ran.
const LUA_RAISE_ONLY_SET = `
  local cur = redis.call('GET', KEYS[1])
  if cur == false or tonumber(ARGV[1]) > tonumber(cur) then
    redis.call('SET', KEYS[1], ARGV[1])
    return 1
  else
    return 0
  end`;

export async function raiseOnlySet(client: Redis, key: string, value: number): Promise<boolean> {
  const r = await (client.eval(LUA_RAISE_ONLY_SET, 1, key, String(value)) as Promise<number>);
  return r === 1;
}
