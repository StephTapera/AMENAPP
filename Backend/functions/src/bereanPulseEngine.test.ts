import * as admin from "firebase-admin";
import {
  BereanPulseEventRecord,
  BereanPulseSignal,
  buildBereanPulseCards,
  detectOpenLoops,
  normalizePermissions,
} from "./bereanPulseEngine";

const ts = (iso: string) => admin.firestore.Timestamp.fromDate(new Date(iso));

function signal(overrides: Partial<BereanPulseSignal> = {}): BereanPulseSignal {
  return {
    id: overrides.id ?? "signal_1",
    source: overrides.source ?? "savedPosts",
    sourceRecordId: overrides.sourceRecordId ?? "record_1",
    title: overrides.title ?? "Saved post not revisited",
    summary: overrides.summary ?? "You saved a post and have not gone back to it yet.",
    timestamp: overrides.timestamp ?? ts("2026-01-01T12:00:00.000Z"),
    sensitivity: overrides.sensitivity ?? "low",
    permissionRequired: overrides.permissionRequired ?? true,
    permissionGranted: overrides.permissionGranted ?? true,
    hashForDeduplication: overrides.hashForDeduplication ?? "saved:1",
    isUserVisible: overrides.isUserVisible ?? true,
    entityType: overrides.entityType ?? "post",
    entityId: overrides.entityId ?? "post_1",
    metadata: overrides.metadata ?? { intent: "learningContinuation", postId: "post_1", openLoop: "true" },
  };
}

function event(overrides: Partial<BereanPulseEventRecord>): BereanPulseEventRecord {
  return {
    id: overrides.id ?? "event_1",
    cardId: overrides.cardId ?? "card_1",
    eventType: overrides.eventType ?? "liked",
    mode: overrides.mode ?? "learning",
    metadata: overrides.metadata ?? { topicKey: "savedPost:post_1" },
    timestamp: overrides.timestamp ?? ts("2026-01-01T13:00:00.000Z"),
  };
}

describe("Berean Pulse engine", () => {
  test("permissions default deny sensitive sources", () => {
    const permissions = normalizePermissions({});
    expect(permissions.prayerJournal).toBe(false);
    expect(permissions.workProjectContext).toBe(false);
    expect(permissions.savedPosts).toBe(true);
  });

  test("denied permission source does not produce cards", () => {
    const cards = buildBereanPulseCards({
      userId: "user_1",
      dateKey: "2026-01-01",
      permissions: { savedPosts: false },
      preferences: { enabled: true },
      signals: [signal({ source: "savedPosts" })],
      feedback: [],
      now: ts("2026-01-01T14:00:00.000Z"),
    });
    expect(cards).toHaveLength(0);
  });

  test("open post action includes a postId payload", () => {
    const cards = buildBereanPulseCards({
      userId: "user_1",
      dateKey: "2026-01-01",
      permissions: { savedPosts: true },
      preferences: { enabled: true },
      signals: [signal({
        source: "savedPosts",
        entityType: "post",
        entityId: "post_42",
        metadata: { intent: "openLoopResolution", openLoop: "true", postId: "post_42" },
      })],
      feedback: [],
      now: ts("2026-01-01T14:00:00.000Z"),
    });

    const openLoopCard = cards.find((card) => card.primaryIntent === "openLoopResolution");
    expect(openLoopCard).toBeDefined();
    expect(openLoopCard?.actionType).toBe("openPost");
    expect(openLoopCard?.actionPayload.postId).toBe("post_42");
  });

  test("feedback changes generation by suppressing hidden topic", () => {
    const cards = buildBereanPulseCards({
      userId: "user_1",
      dateKey: "2026-01-01",
      permissions: { savedPosts: true },
      preferences: { enabled: true },
      signals: [signal()],
      feedback: [event({ eventType: "hidden" })],
      now: ts("2026-01-01T14:00:00.000Z"),
    });
    expect(cards).toHaveLength(0);
  });

  test("open loop detection is based on real signal metadata", () => {
    const loops = detectOpenLoops([
      signal({ id: "a", metadata: { openLoop: "true" } }),
      signal({ id: "b", metadata: { openLoop: "false" } }),
    ]);
    expect(loops.map((item) => item.id)).toEqual(["a"]);
  });
});
