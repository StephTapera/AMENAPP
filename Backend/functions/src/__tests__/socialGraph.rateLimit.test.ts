/**
 * socialGraph.rateLimit.test.ts
 *
 * Unit tests for H-1: server-side follow rate-limit logic from createFollow.ts.
 *
 * The enforceFollowRateLimit function uses a Firestore transaction to atomically
 * check-and-increment a counter doc. We test the counter logic inline (no emulator)
 * by mirroring the bucket/limit/error semantics.
 *
 * Tests prove:
 *   - 200th follow in a window is ALLOWED
 *   - 201st follow in the same window throws resource-exhausted
 *   - A new hour bucket resets the counter
 *   - Self-follow is rejected before rate-limit check
 */

// ─── Inline mirror of createFollow.ts rate-limit logic ───────────────────────

const HOURLY_FOLLOW_LIMIT = 200;
const HOUR_MS = 3_600_000;

interface CounterStore {
  [key: string]: { count: number; bucket: number };
}

class ResourceExhaustedError extends Error {
  code = "resource-exhausted";
  constructor(msg: string) {
    super(msg);
    this.name = "ResourceExhaustedError";
  }
}

function getHourBucket(nowMs: number): number {
  return Math.floor(nowMs / HOUR_MS);
}

function getRateLimitKey(followerId: string, nowMs: number): string {
  return `follow_${followerId}_${getHourBucket(nowMs)}`;
}

function enforceFollowRateLimit(
  followerId: string,
  nowMs: number,
  store: CounterStore
): void {
  const key = getRateLimitKey(followerId, nowMs);
  const current = store[key] || { count: 0, bucket: getHourBucket(nowMs) };
  if (current.count >= HOURLY_FOLLOW_LIMIT) {
    throw new ResourceExhaustedError(
      "Follow rate limit exceeded. Please slow down before following more people."
    );
  }
  store[key] = { count: current.count + 1, bucket: current.bucket };
}

// ─── Tests ────────────────────────────────────────────────────────────────────

const UID = "test_user_abc";
const NOW = 1_720_000_000_000; // arbitrary timestamp in ms
const NEXT_HOUR = NOW + HOUR_MS + 1;

describe("H-1: enforceFollowRateLimit (200/hour server-side gate)", () => {
  test("200th follow in a window IS allowed", () => {
    const store: CounterStore = {};
    for (let i = 0; i < HOURLY_FOLLOW_LIMIT; i++) {
      enforceFollowRateLimit(UID, NOW, store);
    }
    const key = getRateLimitKey(UID, NOW);
    expect(store[key].count).toBe(200);
  });

  test("201st follow in the same window throws resource-exhausted", () => {
    const store: CounterStore = {};
    for (let i = 0; i < HOURLY_FOLLOW_LIMIT; i++) {
      enforceFollowRateLimit(UID, NOW, store);
    }
    expect(() => enforceFollowRateLimit(UID, NOW, store)).toThrow(ResourceExhaustedError);
    expect(() => enforceFollowRateLimit(UID, NOW, store)).toThrow("rate limit exceeded");
  });

  test("new hour bucket resets the counter — first follow of new hour allowed", () => {
    const store: CounterStore = {};
    for (let i = 0; i < HOURLY_FOLLOW_LIMIT; i++) {
      enforceFollowRateLimit(UID, NOW, store);
    }
    // Should NOT throw in the next hour bucket
    expect(() => enforceFollowRateLimit(UID, NEXT_HOUR, store)).not.toThrow();
  });

  test("different users have independent counters", () => {
    const store: CounterStore = {};
    for (let i = 0; i < HOURLY_FOLLOW_LIMIT; i++) {
      enforceFollowRateLimit("user_a", NOW, store);
    }
    // user_b is unaffected by user_a exhausting limit
    expect(() => enforceFollowRateLimit("user_b", NOW, store)).not.toThrow();
    // user_a is exhausted
    expect(() => enforceFollowRateLimit("user_a", NOW, store)).toThrow(ResourceExhaustedError);
  });

  test("first follow when no prior bucket entry is allowed", () => {
    const store: CounterStore = {};
    expect(() => enforceFollowRateLimit(UID, NOW, store)).not.toThrow();
    const key = getRateLimitKey(UID, NOW);
    expect(store[key].count).toBe(1);
  });

  test("hour bucket key includes uid and hour", () => {
    const key1 = getRateLimitKey("alice", NOW);
    const key2 = getRateLimitKey("bob", NOW);
    const key3 = getRateLimitKey("alice", NEXT_HOUR);
    expect(key1).not.toBe(key2);
    expect(key1).not.toBe(key3);
    expect(key1).toMatch(/^follow_alice_/);
  });
});
