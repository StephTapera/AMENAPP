// churchJourney.ts
// Church Journey orchestration layer — gen2 Firebase Cloud Functions
//
// Handles: journey creation, timing recomputation, status promotion,
// reflection seed generation, routine learning, prep suggestions,
// midweek reminder scheduling, and stale journey cleanup.
//
// All server-owned fields (confidenceScore, AI outputs, timing, status
// transitions triggered by schedule) are written exclusively here via
// the admin SDK — never by the client.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { requireAppCheck } from "./trustIntelligence";

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

// ============================================================================
// Types
// ============================================================================

interface JourneyTiming {
    reminderAt: admin.firestore.Timestamp | null;
    prepStartAt: admin.firestore.Timestamp | null;
    departureAt: admin.firestore.Timestamp | null;
    coffeeWindowStartAt: admin.firestore.Timestamp | null;
    coffeeWindowEndAt: admin.firestore.Timestamp | null;
    notesPromptAt: admin.firestore.Timestamp | null;
    reflectionPromptAt: admin.firestore.Timestamp | null;
}

interface JourneyOptions {
    coffeeEnabled: boolean;
    worshipPrepEnabled: boolean;
    scripturePrepEnabled: boolean;
    familyModeEnabled: boolean;
    noteModeEnabled: boolean;
    reflectionEnabled: boolean;
}

interface CreateJourneyRequest {
    churchId: string;
    serviceTimeId?: string;
    serviceLabelSnapshot?: string;
    serviceStartAt: number; // Unix ms
    serviceEndAt: number;   // Unix ms
    options: JourneyOptions;
    usedRoutineId?: string;
    routeEstimateMinutes?: number;
    planSource?: "manual" | "routine" | "suggested";
}

// ============================================================================
// 8.1 createChurchJourney — callable
// ============================================================================

export const createChurchJourney = onCall(
    { region: "us-central1", enforceAppCheck: true },
    async (request) => {
        requireAppCheck(request);

        const uid = request.auth?.uid;
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const data = request.data as CreateJourneyRequest;
        if (!data.churchId || !data.serviceStartAt) {
            throw new HttpsError("invalid-argument", "churchId and serviceStartAt required.");
        }

        // Fetch church to build context snapshot
        const churchDoc = await db.collection("churches").doc(data.churchId).get();
        const church = churchDoc.data() ?? {};

        const serviceStart = admin.firestore.Timestamp.fromMillis(data.serviceStartAt);
        const serviceEnd = admin.firestore.Timestamp.fromMillis(data.serviceEndAt);

        // Compute timing windows
        const timing = computeJourneyTiming({
            serviceStartAt: data.serviceStartAt,
            serviceEndAt: data.serviceEndAt,
            options: data.options,
            routeEstimateMinutes: data.routeEstimateMinutes ?? 20,
            parkingComplexity: church.parkingComplexity ?? "medium",
            quietHours: null,
        });

        // Build context snapshot from church data
        const contextSnapshot = {
            expectedParkingComplexity: church.parkingComplexity ?? "medium",
            weatherSummary: null,
            routeEstimateMinutes: data.routeEstimateMinutes ?? null,
            churchCafeAvailable: church.hasCafe ?? false,
        };

        // Build initial prep module suggestions
        const suggestedPrepModules: string[] = [];
        if (data.options.scripturePrepEnabled) suggestedPrepModules.push("scripture");
        if (data.options.worshipPrepEnabled) suggestedPrepModules.push("worship");
        if (data.options.coffeeEnabled) suggestedPrepModules.push("coffee");

        const journeyRef = db.collection("churchJourneys").doc();
        await journeyRef.set({
            userId: uid,
            churchId: data.churchId,
            churchNameSnapshot: church.name ?? "",
            serviceTimeId: data.serviceTimeId ?? null,
            serviceLabelSnapshot: data.serviceLabelSnapshot ?? null,
            serviceStartAt: serviceStart,
            serviceEndAt: serviceEnd,
            status: "planned",
            planSource: data.planSource ?? "manual",
            timing,
            options: data.options,
            memoryInputs: {
                usedRoutineId: data.usedRoutineId ?? null,
                usedCoffeeTemplateId: null,
                usedPreferenceProfileVersion: null,
            },
            contextSnapshot,
            outputs: {
                suggestedPrepModules,
                suggestedScriptures: church.prepContent?.defaultScriptures ?? [],
                suggestedWorshipLinks: church.prepContent?.worshipLinks ?? [],
                suggestedReminders: [],
            },
            noteSessionId: null,
            reflectionId: null,
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
        });

        // If the user had a routine, optionally auto-generate prep suggestions
        if (data.usedRoutineId && (data.options.scripturePrepEnabled || data.options.worshipPrepEnabled)) {
            // Fire-and-forget async prep suggestions generation
            _generatePrepSuggestionsInternal(journeyRef.id, uid, data.churchId, church).catch(() => {});
        }

        return { journeyId: journeyRef.id };
    }
);

// ============================================================================
// 8.2 updateChurchJourneyTiming — callable
// Recomputes reminder windows when service time or options change.
// ============================================================================

export const updateChurchJourneyTiming = onCall(
    { region: "us-central1", enforceAppCheck: true },
    async (request) => {
        requireAppCheck(request);

        const uid = request.auth?.uid;
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const { journeyId, options, serviceStartAt, serviceEndAt, routeEstimateMinutes } = request.data as {
            journeyId: string;
            options?: Partial<JourneyOptions>;
            serviceStartAt?: number;
            serviceEndAt?: number;
            routeEstimateMinutes?: number;
        };

        if (!journeyId) throw new HttpsError("invalid-argument", "journeyId required.");

        const journeyRef = db.collection("churchJourneys").doc(journeyId);
        const journeyDoc = await journeyRef.get();
        if (!journeyDoc.exists) throw new HttpsError("not-found", "Journey not found.");

        const journey = journeyDoc.data()!;
        if (journey.userId !== uid) throw new HttpsError("permission-denied", "Not your journey.");
        if (["completed", "cancelled"].includes(journey.status)) {
            throw new HttpsError("failed-precondition", "Cannot update timing on a finished journey.");
        }

        // Fetch church for parking complexity
        const churchDoc = await db.collection("churches").doc(journey.churchId).get();
        const church = churchDoc.data() ?? {};

        const resolvedStart = serviceStartAt ?? journey.serviceStartAt.toMillis();
        const resolvedEnd = serviceEndAt ?? journey.serviceEndAt.toMillis();
        const resolvedOptions: JourneyOptions = { ...journey.options, ...(options ?? {}) };

        const timing = computeJourneyTiming({
            serviceStartAt: resolvedStart,
            serviceEndAt: resolvedEnd,
            options: resolvedOptions,
            routeEstimateMinutes: routeEstimateMinutes ?? journey.contextSnapshot.routeEstimateMinutes ?? 20,
            parkingComplexity: church.parkingComplexity ?? journey.contextSnapshot.expectedParkingComplexity ?? "medium",
            quietHours: null,
        });

        await journeyRef.update({
            timing,
            options: resolvedOptions,
            ...(serviceStartAt ? { serviceStartAt: admin.firestore.Timestamp.fromMillis(serviceStartAt) } : {}),
            ...(serviceEndAt ? { serviceEndAt: admin.firestore.Timestamp.fromMillis(serviceEndAt) } : {}),
            updatedAt: FieldValue.serverTimestamp(),
        });

        return { success: true };
    }
);

// ============================================================================
// 8.3 promoteJourneyToPrepActive — scheduled trigger (every 15 min)
// Promotes 'planned' journeys whose prepStartAt window has arrived.
//
// NOTE: Add a Firestore TTL policy on `system/scheduledJobLocks` collection
// with field `expiresAt` set to 7 days. This automatically cleans up old lock documents.
// ============================================================================

export const promoteJourneyToPrepActive = onSchedule(
    { schedule: "every 15 minutes", region: "us-central1" },
    async () => {
        // Idempotency: lock by 15-minute window
        const nowMs = Date.now();
        const windowMs = 15 * 60 * 1000;
        const windowKey = new Date(Math.floor(nowMs / windowMs) * windowMs).toISOString().replace(/[:.]/g, "-");
        const lockRef = db.doc(`system/scheduledJobLocks/promoteJourneyToPrepActive_${windowKey}`);

        const lockAcquired = await db.runTransaction(async (tx) => {
            const snap = await tx.get(lockRef);
            if (snap.exists && snap.data()?.status === "completed") {
                return false;
            }
            tx.set(lockRef, {
                status: "running",
                startedAt: FieldValue.serverTimestamp(),
                windowKey,
                expiresAt: new Date(nowMs + 7 * 24 * 60 * 60 * 1000),
            });
            return true;
        });

        if (!lockAcquired) {
            return;
        }

        try {
            const now = admin.firestore.Timestamp.now();
            const window = admin.firestore.Timestamp.fromMillis(now.toMillis() + 15 * 60 * 1000);

            const snapshot = await db
                .collection("churchJourneys")
                .where("status", "==", "planned")
                .where("timing.prepStartAt", "<=", window)
                .get();

            const batch = db.batch();
            snapshot.docs.forEach((doc) => {
                const journey = doc.data();
                // Only promote if prep is enabled and prepStartAt has passed
                if (
                    journey.options?.worshipPrepEnabled ||
                    journey.options?.scripturePrepEnabled
                ) {
                    batch.update(doc.ref, {
                        status: "prep_active",
                        updatedAt: FieldValue.serverTimestamp(),
                    });
                }
            });

            await batch.commit();

            await lockRef.update({
                status: "completed",
                completedAt: FieldValue.serverTimestamp(),
            });
        } catch (err) {
            await lockRef.update({
                status: "failed",
                error: String(err),
                failedAt: FieldValue.serverTimestamp(),
            });
            throw err;
        }
    }
);

// ============================================================================
// 8.4 promoteJourneyToArrived — callable (user manual check-in)
// ============================================================================

export const promoteJourneyToArrived = onCall(
    { region: "us-central1", enforceAppCheck: true },
    async (request) => {
        requireAppCheck(request);

        const uid = request.auth?.uid;
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const { journeyId } = request.data as { journeyId: string };
        if (!journeyId) throw new HttpsError("invalid-argument", "journeyId required.");

        const journeyRef = db.collection("churchJourneys").doc(journeyId);
        const journeyDoc = await journeyRef.get();
        if (!journeyDoc.exists) throw new HttpsError("not-found", "Journey not found.");

        const journey = journeyDoc.data()!;
        if (journey.userId !== uid) throw new HttpsError("permission-denied", "Not your journey.");

        const validPrior = ["planned", "prep_active"];
        if (!validPrior.includes(journey.status)) {
            throw new HttpsError("failed-precondition", `Cannot arrive from status: ${journey.status}`);
        }

        // Create note session placeholder if noteModeEnabled
        let noteSessionId: string | null = journey.noteSessionId;
        if (journey.options?.noteModeEnabled && !noteSessionId) {
            const churchDoc = await db.collection("churches").doc(journey.churchId).get();
            const church = churchDoc.data() ?? {};
            const sessionRef = db.collection("churchNoteSessions").doc();
            const dateKey = new Date().toISOString().split("T")[0];

            await sessionRef.set({
                userId: uid,
                churchId: journey.churchId,
                journeyId,
                serviceTimeId: journey.serviceTimeId ?? null,
                title: `${church.name ?? "Church"} — ${dateKey}`,
                dateKey,
                sermonTitle: null,
                sermonSpeaker: null,
                expectedScriptureRefs: journey.outputs?.suggestedScriptures ?? [],
                attachedScriptureRefs: [],
                highlightsSummary: [],
                status: "active",
                reflectionSeedGenerated: false,
                createdAt: FieldValue.serverTimestamp(),
                updatedAt: FieldValue.serverTimestamp(),
            });
            noteSessionId = sessionRef.id;
        }

        await journeyRef.update({
            status: "arrived",
            noteSessionId,
            updatedAt: FieldValue.serverTimestamp(),
        });

        // Record attendance
        await db
            .collection("users")
            .doc(uid)
            .collection("churchAttendance")
            .add({
                userId: uid,
                churchId: journey.churchId,
                journeyId,
                serviceTimeId: journey.serviceTimeId ?? null,
                attendedAt: FieldValue.serverTimestamp(),
                source: "manual",
                noteSessionId,
                reflectionId: null,
                createdAt: FieldValue.serverTimestamp(),
            });

        return { success: true, noteSessionId };
    }
);

// ============================================================================
// 8.5 generateReflectionSeedFromNotes — callable
// Summarizes note session content and writes a reflection seed.
// ============================================================================

export const generateReflectionSeedFromNotes = onCall(
    { region: "us-central1", enforceAppCheck: true },
    async (request) => {
        requireAppCheck(request);

        const uid = request.auth?.uid;
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const { noteSessionId } = request.data as { noteSessionId: string };
        if (!noteSessionId) throw new HttpsError("invalid-argument", "noteSessionId required.");

        const sessionRef = db.collection("churchNoteSessions").doc(noteSessionId);
        const sessionDoc = await sessionRef.get();
        if (!sessionDoc.exists) throw new HttpsError("not-found", "Note session not found.");

        const session = sessionDoc.data()!;
        if (session.userId !== uid) throw new HttpsError("permission-denied", "Not your session.");
        if (session.reflectionSeedGenerated) {
            return { success: true, message: "Seed already generated." };
        }

        // Extract likely takeaways from highlights summary
        const highlights: Array<{ type: string; text: string }> = session.highlightsSummary ?? [];
        const keyVerses = highlights.filter((h) => h.type === "Key Verse").map((h) => h.text);
        const convictions = highlights.filter((h) => h.type === "Conviction").map((h) => h.text);
        const actionItems = highlights.filter((h) => h.type === "Action").map((h) => ({
            text: h.text,
            completed: false,
        }));

        // Build reflection pre-seed in Firestore (no AI yet — AI is called lazily by client)
        const journeyRef = db.collection("churchJourneys").doc(session.journeyId);
        const journeyDoc = await journeyRef.get();

        const reflectionRef = db.collection("churchReflections").doc();
        await reflectionRef.set({
            userId: uid,
            churchId: session.churchId,
            journeyId: session.journeyId,
            noteSessionId,
            primaryTakeaway: convictions.length > 0 ? convictions[0] : null,
            applicationText: null,
            prayerText: null,
            verseToCarry: keyVerses.length > 0 ? keyVerses[0] : null,
            actionItems,
            aiSummary: null,
            aiSuggestedPrayer: null,
            aiSuggestedActions: [],
            midweekReminderEnabled: false,
            midweekReminderAt: null,
            status: "draft",
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
        });

        // Mark session as having generated seed + link reflection
        await sessionRef.update({
            reflectionSeedGenerated: true,
            status: "completed",
            updatedAt: FieldValue.serverTimestamp(),
        });

        // Link reflection back to journey
        if (journeyDoc.exists) {
            await journeyRef.update({
                reflectionId: reflectionRef.id,
                status: "reflection_pending",
                updatedAt: FieldValue.serverTimestamp(),
            });
        }

        return { success: true, reflectionId: reflectionRef.id };
    }
);

// ============================================================================
// 8.6 scheduleMidweekReflectionReminder — callable
// ============================================================================

export const scheduleMidweekReflectionReminder = onCall(
    { region: "us-central1", enforceAppCheck: true },
    async (request) => {
        requireAppCheck(request);

        const uid = request.auth?.uid;
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const { reflectionId, reminderDayOffset, quietHoursStart, quietHoursEnd } = request.data as {
            reflectionId: string;
            reminderDayOffset: number; // Days from now (e.g. 3 = Wednesday if Sunday service)
            quietHoursStart?: number;  // Hour 0-23 UTC
            quietHoursEnd?: number;
        };

        if (!reflectionId) throw new HttpsError("invalid-argument", "reflectionId required.");

        const reflectionRef = db.collection("churchReflections").doc(reflectionId);
        const reflectionDoc = await reflectionRef.get();
        if (!reflectionDoc.exists) throw new HttpsError("not-found", "Reflection not found.");

        const reflection = reflectionDoc.data()!;
        if (reflection.userId !== uid) throw new HttpsError("permission-denied", "Not your reflection.");

        // Compute reminder time (midday, respecting quiet hours)
        const reminderDate = new Date();
        reminderDate.setDate(reminderDate.getDate() + (reminderDayOffset ?? 3));
        reminderDate.setHours(10, 0, 0, 0); // Default 10 AM

        // Avoid quiet hours
        const hour = reminderDate.getHours();
        const qStart = quietHoursStart ?? 22;
        const qEnd = quietHoursEnd ?? 7;
        if (
            (qStart < qEnd && hour >= qStart && hour < qEnd) ||
            (qStart >= qEnd && (hour >= qStart || hour < qEnd))
        ) {
            reminderDate.setHours(qEnd + 1, 0, 0, 0);
        }

        const midweekReminderAt = admin.firestore.Timestamp.fromDate(reminderDate);

        // Write reminder timestamp server-side (protected field)
        await reflectionRef.update({
            midweekReminderEnabled: true,
            midweekReminderAt,
            updatedAt: FieldValue.serverTimestamp(),
        });

        // Enqueue a scheduled notification
        await db.collection("scheduledNotifications").add({
            userId: uid,
            type: "midweek_reflection_reminder",
            reflectionId,
            scheduledAt: midweekReminderAt,
            delivered: false,
            deepLinkRoute: `amen://church-journey/reflection/${reflectionId}`,
            title: "Your reflection is waiting",
            body: "You wanted to revisit something from Sunday. Ready?",
            createdAt: FieldValue.serverTimestamp(),
        });

        return { success: true, scheduledAt: midweekReminderAt.toMillis() };
    }
);

// ============================================================================
// 8.7 learnChurchRoutine — Firestore trigger
// Fires when churchAttendance docs are written; detects repeated patterns.
// ============================================================================

export const learnChurchRoutine = onDocumentWritten(
    { document: "users/{userId}/churchAttendance/{attendanceId}", region: "us-central1" },
    async (event) => {
        const userId = event.params.userId;
        const afterData = event.data?.after?.data();
        if (!afterData) return;

        // Look for pattern: ≥3 visits to same church with same serviceTimeId
        const churchId = afterData.churchId;
        const serviceTimeId = afterData.serviceTimeId;
        if (!churchId) return;

        const recentAttendance = await db
            .collection("users")
            .doc(userId)
            .collection("churchAttendance")
            .where("churchId", "==", churchId)
            .where("serviceTimeId", "==", serviceTimeId)
            .orderBy("attendedAt", "desc")
            .limit(4)
            .get();

        if (recentAttendance.size < 3) return;

        // Check if a routine already exists for this church+serviceTime
        const existingRoutine = await db
            .collection("users")
            .doc(userId)
            .collection("churchRoutines")
            .where("churchId", "==", churchId)
            .where("preferredServiceTimeId", "==", serviceTimeId)
            .where("source", "==", "learned")
            .limit(1)
            .get();

        if (!existingRoutine.empty) {
            // Update confidence on existing routine
            await existingRoutine.docs[0].ref.update({
                confidenceScore: Math.min(1.0, (existingRoutine.docs[0].data().confidenceScore ?? 0.5) + 0.1),
                updatedAt: FieldValue.serverTimestamp(),
            });
            return;
        }

        // Create a suggested routine (source='suggested', not auto-active)
        const churchDoc = await db.collection("churches").doc(churchId).get();
        const church = churchDoc.data() ?? {};

        await db
            .collection("users")
            .doc(userId)
            .collection("churchRoutines")
            .add({
                userId,
                churchId,
                churchNameSnapshot: church.name ?? "",
                preferredServiceTimeId: serviceTimeId,
                preferredServiceLabel: church.serviceTimes?.find((s: { id: string }) => s.id === serviceTimeId)?.label ?? null,
                daysOfWeek: [1], // Sunday by default
                planningEnabled: false,
                coffeeEnabled: false,
                coffeeVendorType: null,
                coffeeTemplateId: null,
                worshipPrepEnabled: false,
                scripturePrepEnabled: false,
                familyModeEnabled: false,
                preferredArrivalBufferMinutes: 10,
                preferredPrepLeadMinutes: 30,
                preferredReminderLeadMinutes: 60,
                postServiceReflectionEnabled: false,
                midweekReminderEnabled: false,
                active: false, // Must be explicitly activated by user
                source: "suggested",
                confidenceScore: 0.6,
                createdAt: FieldValue.serverTimestamp(),
                updatedAt: FieldValue.serverTimestamp(),
            });

        // Update rhythm stats
        await _updateChurchRhythm(userId, churchId);
    }
);

// ============================================================================
// 8.8 cleanupStaleChurchJourneys — scheduled daily
//
// NOTE: Add a Firestore TTL policy on `system/scheduledJobLocks` collection
// with field `expiresAt` set to 7 days. This automatically cleans up old lock documents.
// ============================================================================

export const cleanupStaleChurchJourneys = onSchedule(
    { schedule: "every 24 hours", region: "us-central1" },
    async () => {
        const today = new Date().toISOString().slice(0, 10);
        const lockRef = db.doc(`system/scheduledJobLocks/cleanupStaleChurchJourneys_${today}`);

        const lockAcquired = await db.runTransaction(async (tx) => {
            const snap = await tx.get(lockRef);
            if (snap.exists && snap.data()?.status === "completed") {
                return false;
            }
            tx.set(lockRef, {
                status: "running",
                startedAt: FieldValue.serverTimestamp(),
                date: today,
                expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
            });
            return true;
        });

        if (!lockAcquired) {
            return;
        }

        try {
            const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - 30 * 24 * 60 * 60 * 1000);

            // Mark old planned/prep_active journeys as cancelled
            const staleJourneys = await db
                .collection("churchJourneys")
                .where("status", "in", ["planned", "prep_active"])
                .where("serviceStartAt", "<", cutoff)
                .get();

            const batch = db.batch();
            staleJourneys.docs.forEach((doc) => {
                batch.update(doc.ref, {
                    status: "cancelled",
                    updatedAt: FieldValue.serverTimestamp(),
                });
            });

            // Remove delivered scheduled notifications older than 7 days
            const notifCutoff = admin.firestore.Timestamp.fromMillis(Date.now() - 7 * 24 * 60 * 60 * 1000);
            const staleNotifs = await db
                .collection("scheduledNotifications")
                .where("delivered", "==", true)
                .where("scheduledAt", "<", notifCutoff)
                .get();

            staleNotifs.docs.forEach((doc) => {
                batch.delete(doc.ref);
            });

            await batch.commit();

            await lockRef.update({
                status: "completed",
                completedAt: FieldValue.serverTimestamp(),
            });
        } catch (err) {
            await lockRef.update({
                status: "failed",
                error: String(err),
                failedAt: FieldValue.serverTimestamp(),
            });
            throw err;
        }
    }
);

// ============================================================================
// 8.9 generatePrepSuggestions — callable
// ============================================================================

export const generatePrepSuggestions = onCall(
    { region: "us-central1", enforceAppCheck: true },
    async (request) => {
        requireAppCheck(request);

        const uid = request.auth?.uid;
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const { journeyId } = request.data as { journeyId: string };
        if (!journeyId) throw new HttpsError("invalid-argument", "journeyId required.");

        const journeyRef = db.collection("churchJourneys").doc(journeyId);
        const journeyDoc = await journeyRef.get();
        if (!journeyDoc.exists) throw new HttpsError("not-found", "Journey not found.");

        const journey = journeyDoc.data()!;
        if (journey.userId !== uid) throw new HttpsError("permission-denied", "Not your journey.");

        const churchDoc = await db.collection("churches").doc(journey.churchId).get();
        const church = churchDoc.data() ?? {};

        const suggestions = await _generatePrepSuggestionsInternal(journeyId, uid, journey.churchId, church);
        return { success: true, suggestions };
    }
);

// ============================================================================
// Internal helpers
// ============================================================================

function computeJourneyTiming(params: {
    serviceStartAt: number;
    serviceEndAt: number;
    options: JourneyOptions;
    routeEstimateMinutes: number;
    parkingComplexity: "low" | "medium" | "high";
    quietHours: { start: number; end: number } | null;
}): JourneyTiming {
    const { serviceStartAt, serviceEndAt, options, routeEstimateMinutes, parkingComplexity } = params;

    // Parking buffer: low=5min, medium=10min, high=20min
    const parkingBuffer = parkingComplexity === "high" ? 20 : parkingComplexity === "medium" ? 10 : 5;
    // Family mode adds 15min buffer
    const familyBuffer = options.familyModeEnabled ? 15 : 0;
    // Arrival buffer: 10min before service
    const arrivalBuffer = 10;

    const totalLeadMinutes = routeEstimateMinutes + parkingBuffer + familyBuffer + arrivalBuffer;
    const departureMs = serviceStartAt - totalLeadMinutes * 60 * 1000;

    // Coffee window: 20min before departure, 10min window
    const coffeeEnabled = options.coffeeEnabled;
    const coffeeWindowStart = coffeeEnabled
        ? admin.firestore.Timestamp.fromMillis(departureMs - 20 * 60 * 1000)
        : null;
    const coffeeWindowEnd = coffeeEnabled
        ? admin.firestore.Timestamp.fromMillis(departureMs - 5 * 60 * 1000)
        : null;

    // Prep window: 30min before departure if prep enabled
    const prepEnabled = options.worshipPrepEnabled || options.scripturePrepEnabled;
    const prepStartAt = prepEnabled
        ? admin.firestore.Timestamp.fromMillis(departureMs - 30 * 60 * 1000)
        : null;

    // Reminder: 60min before departure
    const reminderAt = admin.firestore.Timestamp.fromMillis(departureMs - 60 * 60 * 1000);

    // Notes prompt: at service start (when user arrives)
    const notesPromptAt = options.noteModeEnabled
        ? admin.firestore.Timestamp.fromMillis(serviceStartAt)
        : null;

    // Reflection prompt: 30min after service ends
    const reflectionPromptAt = options.reflectionEnabled
        ? admin.firestore.Timestamp.fromMillis(serviceEndAt + 30 * 60 * 1000)
        : null;

    return {
        reminderAt,
        prepStartAt,
        departureAt: admin.firestore.Timestamp.fromMillis(departureMs),
        coffeeWindowStartAt: coffeeWindowStart,
        coffeeWindowEndAt: coffeeWindowEnd,
        notesPromptAt,
        reflectionPromptAt,
    };
}

async function _generatePrepSuggestionsInternal(
    journeyId: string,
    userId: string,
    churchId: string,
    church: admin.firestore.DocumentData
): Promise<Record<string, unknown>> {
    const scriptures: string[] =
        church.prepContent?.defaultScriptures?.length > 0
            ? church.prepContent.defaultScriptures.slice(0, 3)
            : ["Psalm 100", "Hebrews 10:24-25", "Colossians 3:16"];

    const worshipLinks: Array<{ title: string; url: string }> =
        church.prepContent?.worshipLinks?.slice(0, 2) ?? [];

    const suggestions = {
        journeyId,
        userId,
        churchId,
        scriptures,
        worshipLinks,
        reflectionPrompt: "What do you hope to receive or bring today?",
        generatedAt: admin.firestore.Timestamp.now(),
    };

    await db.collection("churchJourneyPrepSuggestions").add({
        ...suggestions,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return suggestions;
}

async function _updateChurchRhythm(userId: string, churchId: string): Promise<void> {
    const weekStart = new Date();
    weekStart.setHours(0, 0, 0, 0);
    weekStart.setDate(weekStart.getDate() - weekStart.getDay()); // Sunday
    const weekStartKey = weekStart.toISOString().split("T")[0];

    const rhythmRef = db
        .collection("users")
        .doc(userId)
        .collection("churchRhythms")
        .doc(`${weekStartKey}_${churchId}`);

    await rhythmRef.set(
        {
            weekStartDate: weekStartKey,
            churchVisitsCount: FieldValue.increment(1),
            lastUpdatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
    );
}
