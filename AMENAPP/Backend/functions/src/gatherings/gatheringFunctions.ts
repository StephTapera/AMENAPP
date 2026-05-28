// gatheringFunctions.ts
// Amen Gatherings — Firebase Cloud Callable Functions
//
// Security: App Check enforced by Firebase config. Auth required unless explicitly noted.
// Privacy: prayer/pastoral data never returned without host privilege.
// Counts: always updated server-side via transaction.

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {
  validateCreateGatheringInput,
  validateRsvpInput,
  validatePublishInput,
  sanitizeDescription,
  GatheringValidationError,
} from "./gatheringValidation";
import {
  assertCanCreateGathering,
  fetchGatheringAsHost,
  GatheringPermissionError,
} from "./gatheringPermissions";
import {
  AmenGathering,
  AmenGatheringCounts,
  AmenGatheringFeedCard,
  AmenGatheringRsvp,
} from "./gatheringTypes";

const db = admin.firestore();

// MARK: - createGathering

export const createGathering = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return { errorCode: "auth-required" };

  try {
    validateCreateGatheringInput(data as Record<string, unknown>);
    await assertCanCreateGathering(uid, data["hostType"], data["hostId"]);

    const now = admin.firestore.FieldValue.serverTimestamp();
    const gatheringId = db.collection("gatherings").doc().id;

    const startAt = admin.firestore.Timestamp.fromMillis(data["startAt"] as number);
    const endAt = data["endAt"]
      ? admin.firestore.Timestamp.fromMillis(data["endAt"] as number)
      : undefined;

    const counts: AmenGatheringCounts = {
      going: 0, maybe: 0, declined: 0, invited: 0,
      pendingRequests: 0, waitlisted: 0, checkedIn: 0, comments: 0, photos: 0
    };

    const gathering: Partial<AmenGathering> & { [k: string]: unknown } = {
      gatheringId,
      title: (data["title"] as string).trim(),
      description: sanitizeDescription(data["description"] as string | undefined),
      type: data["type"],
      hostType: data["hostType"],
      hostId: data["hostId"],
      hostName: context.auth?.token?.name ?? "Unknown Host",
      hostVerified: false,
      createdByUid: uid,
      startAt,
      ...(endAt && { endAt }),
      timezone: data["timezone"] ?? null,
      location: data["location"] ?? { type: "tbd" },
      visibility: data["visibility"] ?? "public",
      status: data["publishImmediately"] ? "published" : "draft",
      capacity: data["capacity"] ?? null,
      waitlistEnabled: data["waitlistEnabled"] ?? false,
      access: data["access"] ?? { accessPassEnabled: false, mode: "join", requiresApproval: false, allowGuestPreview: true, allowUnauthenticatedRsvp: false },
      connectedTargets: data["connectedTargets"] ?? {},
      theme: data["theme"] ?? {},
      details: data["details"] ?? {},
      spiritual: data["spiritual"] ?? { allowPrayerRequests: true, allowPastoralFollowUp: true, allowTestimonies: true },
      rsvpSettings: data["rsvpSettings"] ?? { allowGoing: true, allowMaybe: true, allowDecline: true, questionsEnabled: false, guestListVisibility: "attendeesOnly", answersVisibility: "hostsOnly" },
      counts,
      safety: data["safety"] ?? { isSensitive: false, isYouthRelated: false, requiresModeration: false, allowPublicComments: true, prayerRequestsPrivateByDefault: true },
      audit: { createdAt: now, updatedAt: now, ...(data["publishImmediately"] && { publishedAt: now }) },
    };

    const batch = db.batch();
    batch.set(db.collection("gatherings").doc(gatheringId), gathering);

    // Store questions as subcollection
    const questions = data["questions"] as unknown[] | undefined;
    if (Array.isArray(questions)) {
      questions.forEach((q: unknown, i) => {
        const question = q as Record<string, unknown>;
        const qRef = db.collection("gatherings").doc(gatheringId).collection("questions").doc();
        batch.set(qRef, { questionId: qRef.id, sortOrder: i, ...question });
      });
    }

    await batch.commit();

    // Chain Access Pass creation when caller opts in (non-fatal: gathering is still
    // created even if pass creation fails — host can enable the pass later).
    let accessPassId: string | null = null;
    let qrPayload: string | null = null;
    let shareLink = `https://amen.app/gathering/${gatheringId}`;

    const accessConfig = data["access"] as Record<string, unknown> | undefined;
    if (accessConfig?.["accessPassEnabled"] === true) {
      try {
        const passRef = db.collection("accessPasses").doc();
        accessPassId = passRef.id;
        const token = db.collection("accessPassTokens").doc().id;
        qrPayload = `https://amen.app/pass/${token}`;
        shareLink = `https://amen.app/gathering/${gatheringId}?pass=${token}`;
        await passRef.set({
          passId: accessPassId,
          targetType: "gathering",
          targetId: gatheringId,
          mode: accessConfig["mode"] ?? "join",
          requiresApproval: accessConfig["requiresApproval"] ?? false,
          token,
          createdByUid: uid,
          createdAt: now,
          isActive: true,
        });
        await db.collection("gatherings").doc(gatheringId).update({
          "access.accessPassId": accessPassId,
          "access.shareLink": shareLink,
          "audit.updatedAt": now,
        });
      } catch (passError) {
        console.warn("[createGathering] Access pass creation failed (non-fatal):", passError);
        accessPassId = null;
        qrPayload = null;
        shareLink = `https://amen.app/gathering/${gatheringId}`;
      }
    }

    return {
      gatheringId,
      accessPassId,
      shareLink,
      qrPayload,
      universalLink: `https://amen.app/gathering/${gatheringId}`,
    };
  } catch (e) {
    if (e instanceof GatheringValidationError) return { errorCode: e.code };
    if (e instanceof GatheringPermissionError) return { errorCode: e.code };
    console.error("[createGathering]", e);
    return { errorCode: "unknown" };
  }
});

// MARK: - publishGathering

export const publishGathering = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return { errorCode: "auth-required" };

  try {
    validatePublishInput(data as Record<string, unknown>);
    const snap = await fetchGatheringAsHost(uid, data["gatheringId"] as string);
    const gathering = snap.data() as AmenGathering;

    if (gathering.status === "cancelled") {
      return { errorCode: "cancelled" };
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    await snap.ref.update({
      status: "published",
      "audit.updatedAt": now,
      "audit.publishedAt": now,
    });

    return {
      gatheringId: gathering.gatheringId,
      shareLink: `https://amen.app/gathering/${gathering.gatheringId}`,
    };
  } catch (e) {
    if (e instanceof GatheringPermissionError) return { errorCode: e.code };
    console.error("[publishGathering]", e);
    return { errorCode: "unknown" };
  }
});

// MARK: - updateGathering

export const updateGathering = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return { errorCode: "auth-required" };

  try {
    const snap = await fetchGatheringAsHost(uid, data["gatheringId"] as string);
    const updates: Record<string, unknown> = {
      "audit.updatedAt": admin.firestore.FieldValue.serverTimestamp(),
    };

    if (data["title"]) updates["title"] = (data["title"] as string).trim();
    if (data["description"] !== undefined) updates["description"] = sanitizeDescription(data["description"] as string);
    if (data["startAt"]) updates["startAt"] = admin.firestore.Timestamp.fromMillis(data["startAt"] as number);
    if (data["endAt"]) updates["endAt"] = admin.firestore.Timestamp.fromMillis(data["endAt"] as number);
    if (data["location"]) updates["location"] = data["location"];
    if (data["visibility"]) updates["visibility"] = data["visibility"];
    if (data["details"]) updates["details"] = data["details"];
    if (data["spiritual"]) updates["spiritual"] = data["spiritual"];
    if (data["theme"]) updates["theme"] = data["theme"];
    if (data["access"]) updates["access"] = data["access"];
    if (data["rsvpSettings"]) updates["rsvpSettings"] = data["rsvpSettings"];

    await snap.ref.update(updates);
    return { success: true };
  } catch (e) {
    if (e instanceof GatheringPermissionError) return { errorCode: e.code };
    console.error("[updateGathering]", e);
    return { errorCode: "unknown" };
  }
});

// MARK: - cancelGathering

export const cancelGathering = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return { errorCode: "auth-required" };

  try {
    const snap = await fetchGatheringAsHost(uid, data["gatheringId"] as string);
    await snap.ref.update({
      status: "cancelled",
      "audit.updatedAt": admin.firestore.FieldValue.serverTimestamp(),
      "audit.cancelledAt": admin.firestore.FieldValue.serverTimestamp(),
      "audit.cancelledByUid": uid,
    });
    return { success: true };
  } catch (e) {
    if (e instanceof GatheringPermissionError) return { errorCode: e.code };
    console.error("[cancelGathering]", e);
    return { errorCode: "unknown" };
  }
});

// MARK: - duplicateGathering

export const duplicateGathering = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return { errorCode: "auth-required" };

  try {
    const snap = await fetchGatheringAsHost(uid, data["gatheringId"] as string);
    const original = snap.data() as AmenGathering;

    const newId = db.collection("gatherings").doc().id;
    const now = admin.firestore.FieldValue.serverTimestamp();

    const duplicate = {
      ...original,
      gatheringId: newId,
      title: `${original.title} (Copy)`,
      status: "draft",
      counts: { going: 0, maybe: 0, declined: 0, invited: 0, pendingRequests: 0, waitlisted: 0, checkedIn: 0, comments: 0, photos: 0 },
      audit: { createdAt: now, updatedAt: now },
    };

    await db.collection("gatherings").doc(newId).set(duplicate);
    return { gatheringId: newId };
  } catch (e) {
    if (e instanceof GatheringPermissionError) return { errorCode: e.code };
    console.error("[duplicateGathering]", e);
    return { errorCode: "unknown" };
  }
});

// MARK: - getGatheringPreview

export const getGatheringPreview = functions.https.onCall(async (data, context) => {
  const gatheringId = data["gatheringId"] as string | undefined;
  if (!gatheringId) return { errorCode: "missing-gathering-id" };

  try {
    const snap = await db.collection("gatherings").doc(gatheringId).get();
    if (!snap.exists) return { errorCode: "not-found" };

    const g = snap.data() as AmenGathering;

    if (g.status === "cancelled") return { errorCode: "cancelled" };

    const isPublic = g.visibility === "public" || g.visibility === "unlisted";
    const uid = context.auth?.uid;
    const isHost = uid === g.createdByUid;

    if (!isPublic && !isHost) {
      if (!uid) return { errorCode: "auth-required" };
      return { errorCode: "permission-denied" };
    }

    // Shape the response — strip private fields for non-hosts
    return shapeGatheringPreview(g, isHost);
  } catch (e) {
    console.error("[getGatheringPreview]", e);
    return { errorCode: "unknown" };
  }
});

// MARK: - rsvpToGathering

export const rsvpToGathering = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return { errorCode: "auth-required" };

  try {
    validateRsvpInput(data as Record<string, unknown>);

    const gatheringId = data["gatheringId"] as string;
    const status = data["status"] as "going" | "maybe" | "declined";

    const gatheringRef = db.collection("gatherings").doc(gatheringId);
    const rsvpRef = gatheringRef.collection("rsvps").doc(uid);

    await db.runTransaction(async (tx) => {
      const gSnap = await tx.get(gatheringRef);
      if (!gSnap.exists) throw new Error("not-found");

      const g = gSnap.data() as AmenGathering;
      if (g.status !== "published") throw new Error("cancelled");
      if (g.access.requiresApproval) throw new Error("approval-required");

      const now = admin.firestore.Timestamp.now();
      const existingSnap = await tx.get(rsvpRef);
      const existingStatus = existingSnap.data()?.["status"] as string | undefined;

      const rsvp: Partial<AmenGatheringRsvp> & { [k: string]: unknown } = {
        uid,
        gatheringId,
        status,
        requestedPrayer: data["requestedPrayer"] ?? false,
        // requestedPastoralFollowUp stored but never logged to analytics
        requestedPastoralFollowUp: data["requestedPastoralFollowUp"] ?? false,
        updatedAt: now,
      };

      if (!existingSnap.exists) {
        rsvp["createdAt"] = now;
      }

      // Capacity check
      if (status === "going" && g.capacity) {
        const currentGoing = g.counts.going;
        if (currentGoing >= g.capacity) {
          if (g.waitlistEnabled) {
            rsvp["status"] = "waitlisted";
          } else {
            throw new Error("capacity-full");
          }
        }
      }

      tx.set(rsvpRef, rsvp, { merge: true });

      // Update counts atomically
      const countUpdates: Record<string, unknown> = {
        "audit.updatedAt": admin.firestore.FieldValue.serverTimestamp(),
      };
      if (existingStatus && existingStatus !== status) {
        countUpdates[`counts.${existingStatus}`] = admin.firestore.FieldValue.increment(-1);
      }
      countUpdates[`counts.${rsvp["status"]}`] = admin.firestore.FieldValue.increment(1);
      tx.update(gatheringRef, countUpdates);
    });

    return { success: true };
  } catch (e) {
    if (e instanceof Error) {
      const knownCodes = ["not-found", "cancelled", "capacity-full", "approval-required"];
      if (knownCodes.includes(e.message)) return { errorCode: e.message };
    }
    console.error("[rsvpToGathering]", e);
    return { errorCode: "unknown" };
  }
});

// MARK: - checkInToGathering

export const checkInToGathering = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return { errorCode: "auth-required" };

  const gatheringId = data["gatheringId"] as string;
  const accessPassId = data["accessPassId"] as string;

  try {
    // Verify access pass is valid for this gathering
    const passSnap = await db.collection("accessPasses").doc(accessPassId).get();
    if (!passSnap.exists || passSnap.data()?.["status"] !== "active") {
      return { errorCode: "invalid-pass" };
    }
    if (passSnap.data()?.["targetId"] !== gatheringId) {
      return { errorCode: "invalid-pass" };
    }

    const gatheringRef = db.collection("gatherings").doc(gatheringId);
    const rsvpRef = gatheringRef.collection("rsvps").doc(uid);
    const now = admin.firestore.Timestamp.now();

    await db.runTransaction(async (tx) => {
      const gSnap = await tx.get(gatheringRef);
      if (!gSnap.exists) throw new Error("not-found");
      if ((gSnap.data() as AmenGathering).status !== "published") throw new Error("cancelled");

      tx.set(rsvpRef, {
        uid, gatheringId, status: "going",
        checkedInAt: now, updatedAt: now, createdAt: now,
      }, { merge: true });

      tx.update(gatheringRef, {
        "counts.checkedIn": admin.firestore.FieldValue.increment(1),
        "audit.updatedAt": admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return { success: true, checkedInAt: now.toMillis() };
  } catch (e) {
    if (e instanceof Error && ["not-found", "cancelled"].includes(e.message)) {
      return { errorCode: e.message };
    }
    console.error("[checkInToGathering]", e);
    return { errorCode: "unknown" };
  }
});

// MARK: - listGatheringsFeed

export const listGatheringsFeed = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  const limit = Math.min((data["limit"] as number) || 30, 100);

  try {
    let query: admin.firestore.Query = db.collection("gatherings")
      .where("status", "==", "published")
      .where("visibility", "in", ["public", "unlisted"])
      .orderBy("startAt", "asc")
      .limit(limit);

    if (data["type"]) query = query.where("type", "==", data["type"]);
    if (data["hostId"]) query = query.where("hostId", "==", data["hostId"]);
    if (data["churchId"]) query = query.where("connectedTargets.churchId", "==", data["churchId"]);

    const snap = await query.get();
    const gatherings: AmenGatheringFeedCard[] = [];

    for (const doc of snap.docs) {
      const g = doc.data() as AmenGathering;
      gatherings.push(shapeGatheringFeedCard(g, uid));
    }

    return { gatherings };
  } catch (e) {
    console.error("[listGatheringsFeed]", e);
    return { gatherings: [] };
  }
});

// MARK: - listHostGatherings

export const listHostGatherings = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return { errorCode: "auth-required" };

  try {
    const snap = await db.collection("gatherings")
      .where("createdByUid", "==", uid)
      .orderBy("startAt", "desc")
      .limit(50)
      .get();

    const gatherings = snap.docs.map((doc) => shapeGatheringPreview(doc.data() as AmenGathering, true));
    return { gatherings };
  } catch (e) {
    console.error("[listHostGatherings]", e);
    return { gatherings: [] };
  }
});

// MARK: - listGatheringRsvps

export const listGatheringRsvps = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return { errorCode: "auth-required" };

  const gatheringId = data["gatheringId"] as string;

  try {
    const gSnap = await db.collection("gatherings").doc(gatheringId).get();
    if (!gSnap.exists) return { errorCode: "not-found" };

    const g = gSnap.data() as AmenGathering;
    const isHost = g.createdByUid === uid;

    const guestListVisibility = g.rsvpSettings.guestListVisibility;
    if (guestListVisibility === "hostsOnly" && !isHost) {
      return { errorCode: "permission-denied" };
    }
    if (guestListVisibility === "attendeesOnly") {
      const myRsvp = await db.collection("gatherings").doc(gatheringId).collection("rsvps").doc(uid).get();
      if (!myRsvp.exists) return { errorCode: "permission-denied" };
    }

    const rsvpSnap = await db.collection("gatherings").doc(gatheringId).collection("rsvps")
      .orderBy("createdAt", "asc")
      .limit(500)
      .get();

    const rsvps = rsvpSnap.docs.map((doc) => {
      const r = doc.data() as AmenGatheringRsvp;
      // Hosts see everything; attendees see displayName, photoURL, status, checkedInAt only
      if (isHost) return r;
      const { uid: rUid, gatheringId: rGid, status, displayName, photoURL, checkedInAt, createdAt, updatedAt } = r;
      return { uid: rUid, gatheringId: rGid, status, displayName, photoURL, checkedInAt, createdAt, updatedAt };
    });

    return { rsvps };
  } catch (e) {
    console.error("[listGatheringRsvps]", e);
    return { rsvps: [] };
  }
});

// MARK: - createGatheringQuestion

export const createGatheringQuestion = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return { errorCode: "auth-required" };

  try {
    await fetchGatheringAsHost(uid, data["gatheringId"] as string);
    const qRef = db.collection("gatherings").doc(data["gatheringId"] as string).collection("questions").doc();
    await qRef.set({ questionId: qRef.id, ...data });
    return { questionId: qRef.id };
  } catch (e) {
    if (e instanceof GatheringPermissionError) return { errorCode: e.code };
    return { errorCode: "unknown" };
  }
});

// MARK: - deleteGatheringQuestion

export const deleteGatheringQuestion = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return { errorCode: "auth-required" };

  try {
    await fetchGatheringAsHost(uid, data["gatheringId"] as string);
    await db.collection("gatherings").doc(data["gatheringId"] as string).collection("questions").doc(data["questionId"] as string).delete();
    return { success: true };
  } catch (e) {
    if (e instanceof GatheringPermissionError) return { errorCode: e.code };
    return { errorCode: "unknown" };
  }
});

// MARK: - sendGatheringUpdate

export const sendGatheringUpdate = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return { errorCode: "auth-required" };

  try {
    const snap = await fetchGatheringAsHost(uid, data["gatheringId"] as string);
    const gathering = snap.data() as AmenGathering;

    // Store update record
    await snap.ref.collection("updates").add({
      title: data["title"],
      body: data["body"],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      sentByUid: uid,
    });

    // Fan-out to RSVPed attendees (simplified — production should use task queues)
    const rsvpSnap = await snap.ref.collection("rsvps")
      .where("status", "in", ["going", "maybe"])
      .limit(1000)
      .get();

    const tokens: string[] = [];
    for (const rsvpDoc of rsvpSnap.docs) {
      const rsvpUid = rsvpDoc.data()["uid"] as string;
      const tokenDoc = await db.collection("users").doc(rsvpUid).collection("fcmTokens").limit(1).get();
      tokenDoc.docs.forEach((t) => tokens.push(t.data()["token"] as string));
    }

    if (tokens.length > 0) {
      await admin.messaging().sendEachForMulticast({
        tokens,
        notification: {
          title: `${gathering.title}: ${data["title"]}`,
          body: data["body"] as string,
        },
        data: {
          type: "gathering_update",
          gatheringId: gathering.gatheringId,
        },
      });
    }

    return { success: true, notified: tokens.length };
  } catch (e) {
    if (e instanceof GatheringPermissionError) return { errorCode: e.code };
    console.error("[sendGatheringUpdate]", e);
    return { errorCode: "unknown" };
  }
});

// MARK: - Privacy Shapers

function shapeGatheringPreview(
  g: AmenGathering,
  isHost: boolean
): Record<string, unknown> {
  const base: Record<string, unknown> = {
    gatheringId: g.gatheringId,
    title: g.title,
    description: g.description,
    type: g.type,
    hostType: g.hostType,
    hostId: g.hostId,
    hostName: g.hostName,
    hostVerified: g.hostVerified,
    createdByUid: g.createdByUid,
    startAt: g.startAt.toMillis(),
    endAt: g.endAt?.toMillis() ?? null,
    timezone: g.timezone ?? null,
    location: g.location,
    visibility: g.visibility,
    status: g.status,
    capacity: g.capacity ?? null,
    waitlistEnabled: g.waitlistEnabled,
    access: g.access,
    connectedTargets: g.connectedTargets,
    theme: g.theme,
    details: g.details,
    spiritual: {
      prayerFocus: g.spiritual.prayerFocus,
      scriptureReference: g.spiritual.scriptureReference,
      allowPrayerRequests: g.spiritual.allowPrayerRequests,
      allowPastoralFollowUp: g.spiritual.allowPastoralFollowUp,
      allowTestimonies: g.spiritual.allowTestimonies,
    },
    rsvpSettings: g.rsvpSettings,
    counts: g.counts,
    safety: g.safety,
  };

  return base;
}

function shapeGatheringFeedCard(
  g: AmenGathering,
  uid: string | undefined
): AmenGatheringFeedCard {
  return {
    gatheringId: g.gatheringId,
    title: g.title,
    type: g.type,
    hostName: g.hostName,
    hostVerified: g.hostVerified,
    coverImageUrl: g.theme.coverImageUrl,
    gradientName: g.theme.gradientName,
    startAt: g.startAt.toMillis(),
    location: {
      type: g.location.type,
      name: g.location.name,
      city: g.location.city,
      onlineUrl: g.location.onlineUrl,
      displaySummary: locationDisplaySummary(g.location),
    },
    visibility: g.visibility,
    accessMode: g.access.mode,
    rsvpCount: g.counts.going,
    userRsvpStatus: undefined,
    isSaved: false,
    scriptureReference: g.theme.scriptureReference,
  };
}

function locationDisplaySummary(location: AmenGathering["location"]): string {
  switch (location.type) {
    case "online": return "Online";
    case "hybrid": return location.name ? `Hybrid · ${location.name}` : "Hybrid";
    case "tbd": return "Location TBD";
    default: return location.name ?? location.city ?? "In Person";
  }
}
