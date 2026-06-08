// getAmbientContext.ts — Ambient OS · Context Engine Cloud Function
// FROZEN v1 · 2026-06-01
//
// Callable (App Check + Auth gated). Aggregates AmbientContext from existing
// Firestore collections. Returns lightweight *Ref pointers — no bodies, no PII
// beyond display name.
//
// Agent A owns the implementation below the IMPLEMENTATION marker.

import * as functions from "firebase-functions/v2";
import { CallableRequest, onCall } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {
  AmbientContext, AmbientMode,
  PrayerRef, NoteRef, ThreadRef, EventRef, BroadcastRef,
  AmbientBereanSuggestion,
} from "./types";

// ─── Callable contract (App Check enforced in prod; relaxed for emulator) ───

export const getAmbientContext = onCall(
  { enforceAppCheck: true, maxInstances: 50, timeoutSeconds: 15 },
  async (req: CallableRequest<{ mode?: AmbientMode }>) => {
    if (!req.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required");

    const uid  = req.auth.uid;
    const mode = req.data?.mode ?? "default";
    const db   = admin.firestore();

    // ── IMPLEMENTATION: Agent A fills in each collector below ──────────────

    const [
      userSnap, prayerSnap, notesSnap, threadsSnap,
      calSnap, churchSnap, selahSnap, ariseSnap,
    ] = await Promise.all([
      db.collection("users").doc(uid).get(),
      db.collection("users").doc(uid).collection("prayers")
        .where("status", "in", ["open", "awaitingResponse"])
        .orderBy("createdAt", "desc").limit(5).get(),
      db.collection("users").doc(uid).collection("churchNotes")
        .where("status", "==", "draft")
        .orderBy("editedAt", "desc").limit(3).get(),
      db.collection("messages").where("participants", "array-contains", uid)
        .where("needsFollowUp", "==", true)
        .orderBy("lastMessageAt", "desc").limit(5).get(),
      db.collection("users").doc(uid).collection("calendarEvents")
        .where("startsAt", ">=", todayISO())
        .where("startsAt", "<", tomorrowISO())
        .orderBy("startsAt").limit(10).get(),
      db.collection("users").doc(uid).get(),  // church sub-query handled below
      db.collection("users").doc(uid).collection("selahProgress").doc("current").get(),
      db.collection("ariseBroadcasts")
        .where("scheduledAt", ">=", nowISO())
        .orderBy("scheduledAt").limit(3).get(),
    ]);

    const userData = userSnap.data() ?? {};
    const firstName: string = userData.firstName ?? "Friend";
    const tz: string = userData.timezone ?? "America/New_York";
    const localTime: string = new Date().toISOString();

    // Prayer
    const awaitingResponse: PrayerRef[] = prayerSnap.docs.map(d => ({
      id: d.id,
      title: d.data().title ?? "Prayer Request",
      deepLink: `amen://prayer/${d.id}`,
      createdAt: d.data().createdAt?.toDate?.()?.toISOString() ?? nowISO(),
    }));

    // Notes
    const unfinished: NoteRef[] = notesSnap.docs.map(d => ({
      id: d.id,
      title: d.data().title ?? "Untitled Note",
      deepLink: `amen://notes/${d.id}`,
      editedAt: d.data().editedAt?.toDate?.()?.toISOString() ?? nowISO(),
    }));

    // Messages
    const needingFollowUp: ThreadRef[] = threadsSnap.docs.map(d => ({
      id: d.id,
      title: d.data().title ?? "Conversation",
      deepLink: `amen://messages/${d.id}`,
      lastMessageAt: d.data().lastMessageAt?.toDate?.()?.toISOString() ?? nowISO(),
    }));
    const unreadSnap = await db.collection("messages")
      .where("participants", "array-contains", uid)
      .where("unreadBy", "array-contains", uid)
      .count().get();
    const unreadThreads: number = unreadSnap.data().count;

    // Calendar
    const todayEvents: EventRef[] = calSnap.docs.map(d => ({
      id: d.id,
      title: d.data().title ?? "Event",
      deepLink: `amen://calendar/${d.id}`,
      startsAt: d.data().startsAt?.toDate?.()?.toISOString() ?? nowISO(),
      endsAt: d.data().endsAt?.toDate?.()?.toISOString(),
    }));
    const nextEvent: EventRef | undefined = todayEvents[0];

    // Church (upcoming events from user's primary church)
    const churchId: string = userData.primaryChurchId ?? "";
    let upcomingEvents: EventRef[] = [];
    let nextService: EventRef | undefined;
    if (churchId) {
      const churchEventsSnap = await db.collection("churches").doc(churchId)
        .collection("events")
        .where("startsAt", ">=", nowISO())
        .orderBy("startsAt").limit(3).get();
      upcomingEvents = churchEventsSnap.docs.map(d => ({
        id: d.id,
        title: d.data().title ?? "Service",
        deepLink: `amen://church/${churchId}/event/${d.id}`,
        startsAt: d.data().startsAt?.toDate?.()?.toISOString() ?? nowISO(),
        endsAt: d.data().endsAt?.toDate?.()?.toISOString(),
      }));
      nextService = upcomingEvents.find(e => e.title?.toLowerCase().includes("service"))
        ?? upcomingEvents[0];
    }

    // Selah
    const selahData = selahSnap.exists ? selahSnap.data()! : {};
    const streakDays: number = selahData.streakDays ?? 0;
    const resumeAt = selahData.book
      ? { book: selahData.book, chapter: selahData.chapter ?? 1, deepLink: `amen://selah/${selahData.book}/${selahData.chapter ?? 1}` }
      : undefined;

    // Arise
    const upcomingBroadcasts: BroadcastRef[] = ariseSnap.docs.map(d => ({
      id: d.id,
      title: d.data().title ?? "Broadcast",
      deepLink: `amen://arise/${d.id}`,
      scheduledAt: d.data().scheduledAt?.toDate?.()?.toISOString() ?? nowISO(),
    }));

    // Berean suggestion (advisory only — never auto-acts)
    const bereanSuggestion: AmbientBereanSuggestion | undefined =
      streakDays === 0
        ? { kind: "study", label: "Start your Selah reading today", deepLink: "amen://selah" }
        : awaitingResponse.length > 0
          ? { kind: "pray", label: `You have ${awaitingResponse.length} prayer${awaitingResponse.length > 1 ? "s" : ""} waiting`, deepLink: "amen://prayer" }
          : undefined;

    const context: AmbientContext = {
      generatedAt: nowISO(),
      user: { id: uid, firstName, localTime, tz },
      prayer: { awaitingResponse, openRequests: awaitingResponse.length },
      notes: { unfinished, lastEditedAt: unfinished[0]?.editedAt },
      messages: { needingFollowUp, unreadThreads },
      calendar: { today: todayEvents, nextEvent },
      church: { upcomingEvents, nextService },
      selah: { streakDays, resumeAt },
      arise: { upcomingBroadcasts },
      bereanSuggestion,
      mode,
    };

    return context;
  }
);

// ─── Helpers ────────────────────────────────────────────────────────────────

function nowISO(): string { return new Date().toISOString(); }

function todayISO(): string {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d.toISOString();
}

function tomorrowISO(): string {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  d.setHours(0, 0, 0, 0);
  return d.toISOString();
}
