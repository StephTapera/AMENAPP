import { toSafeDiscoverTelemetryPayload } from "./discoverTelemetry";

describe("discoverTelemetry", () => {
  it("keeps only structured safe fields", () => {
    const payload = toSafeDiscoverTelemetryPayload({
      uid: "user-123",
      event: "tap",
      itemId: "item-456",
      candidate_count: 12,
      latency_ms: 34,
      ok: true,
      caption: "private caption text",
      requestBody: { nested: "secret" },
      error: new Error("secret stack"),
    });

    expect(payload).toEqual({
      uid: "user-123",
      event: "tap",
      itemId: "item-456",
      candidate_count: 12,
      latency_ms: 34,
      ok: true,
      inputFieldCount: 9,
      droppedFieldCount: 3,
    });
  });

  it("drops unsupported value types for otherwise safe keys", () => {
    const payload = toSafeDiscoverTelemetryPayload({
      uid: { id: "user-123" },
      event: "   ",
      latency_ms: Number.NaN,
      cached: false,
    });

    expect(payload).toEqual({
      cached: false,
      inputFieldCount: 4,
      droppedFieldCount: 3,
    });
  });
});
