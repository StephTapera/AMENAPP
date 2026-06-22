import test from "node:test";
import assert from "node:assert/strict";

import {
  buildCanonicalRecord,
  buildGroupKey,
  buildPushEnvelope,
  buildRoute,
  classifyEvent,
  computePriority,
  privacySafePreview,
} from "../notificationRoutingPipeline.entry";

test("groupKey prevents mixed-intent collision", () => {
  const prayerSupport = classifyEvent({
    id: "event-1",
    recipientId: "user-1",
    type: "prayer_supported",
    targetType: "prayer_request",
    targetId: "prayer-1",
  });
  const prayerReply = classifyEvent({
    id: "event-2",
    recipientId: "user-1",
    type: "prayer_reply",
    targetType: "prayer_request",
    targetId: "prayer-1",
  });

  assert.notEqual(
    buildGroupKey(
        {id: "event-1", recipientId: "user-1", type: "prayer_supported", targetType: "prayer_request", targetId: "prayer-1"},
        prayerSupport,
    ),
    buildGroupKey(
        {id: "event-2", recipientId: "user-1", type: "prayer_reply", targetType: "prayer_request", targetId: "prayer-1"},
        prayerReply,
    ),
  );
});

test("priority bucket and score reflect reply urgency", () => {
  const classification = classifyEvent({
    id: "event-1",
    recipientId: "user-1",
    type: "prayer_reply",
    body: "A pastor replied.",
  });

  assert.deepEqual(computePriority(classification), {bucket: "P0", score: 100});
});

test("private prayer preview never exposes raw text", () => {
  const event = {
    id: "event-1",
    recipientId: "user-1",
    type: "prayer_reply" as const,
    body: "My private diagnosis is getting worse.",
    privacyLevel: "sensitive" as const,
  };

  const preview = privacySafePreview(event, classifyEvent(event));

  assert.equal(preview, "Someone responded with care.");
  assert.ok(!preview.includes("diagnosis"));
});

test("route building uses canonical event detail destinations", () => {
  const event = {
    id: "event-1",
    recipientId: "user-1",
    type: "church_update" as const,
    targetType: "event",
    targetId: "event-99",
    metadata: {openInCalendar: "true"},
  };

  const route = buildRoute(event, classifyEvent(event));

  assert.equal(route.targetRouteType, "add_to_calendar");
  assert.deepEqual(route.routePayload, {eventId: "event-99"});
});

test("canonical record produces protected fallback for unknown types", () => {
  const record = buildCanonicalRecord({
    id: "event-1",
    recipientId: "user-1",
    type: "system",
    body: "unmodeled payload",
    previewText: "unmodeled payload",
  });

  assert.equal(record.classificationSource, "fallback");
  assert.equal(record.fallbackReason, "unknown_or_system_type");
  assert.equal(record.targetRouteType, "notifications_inbox");
  assert.deepEqual(record.routePayload, {});
});

test("push payload uses canonical route and sanitized body", () => {
  const record = buildCanonicalRecord({
    id: "event-1",
    recipientId: "user-1",
    actorId: "actor-1",
    actorDisplayName: "Grace",
    type: "church_note_shared",
    targetType: "church_note",
    targetId: "note-7",
    body: "Shared note body",
    previewText: "Shared note body",
  });

  const envelope = buildPushEnvelope("token-1", {
    id: "pending-1",
    notificationGroupId: record.id,
    recipientId: "user-1",
    pushToken: "token-1",
    routePayload: record.routePayload,
    targetRouteType: record.targetRouteType,
    fallbackRouteType: record.fallbackRouteType,
    fallbackRoutePayload: record.fallbackRoutePayload,
    openBehavior: record.openBehavior,
    type: record.type,
    title: record.title,
    body: record.previewText ?? "",
    badgeCount: 4,
    status: "pending",
    retryCount: 0,
    maxRetries: 4,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
  });

  assert.equal(envelope.data.targetRouteType, "church_note");
  assert.equal(envelope.data.routePayload, JSON.stringify({noteId: "note-7"}));
  assert.equal(envelope.notification?.body, "Shared note body");
});
