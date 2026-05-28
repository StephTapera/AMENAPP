import * as admin from "firebase-admin";
import {HttpsError} from "firebase-functions/v2/https";
import type {AmenIntegrationProvider, AmenMeeting, CreateMeetingInput} from "../models";
import {getDecryptedIntegrationTokens} from "../tokens/TokenVault";
import {getProviderAdapter} from "../providers/providerRegistry";

const db = admin.firestore();

function parseDate(value: unknown, field: string): Date {
    if (typeof value !== "string") throw new HttpsError("invalid-argument", `${field} is required.`);
    const date = new Date(value);
    if (!Number.isFinite(date.getTime())) throw new HttpsError("invalid-argument", `${field} must be an ISO date.`);
    return date;
}

function validateMeetingInput(data: Record<string, unknown>): CreateMeetingInput {
    const title = typeof data.title === "string" ? data.title.trim() : "";
    if (title.length < 3 || title.length > 120) {
        throw new HttpsError("invalid-argument", "title must be 3-120 characters.");
    }

    const startTime = parseDate(data.startTime, "startTime");
    const endTime = parseDate(data.endTime, "endTime");
    const durationMs = endTime.getTime() - startTime.getTime();
    if (durationMs < 15 * 60 * 1000 || durationMs > 8 * 60 * 60 * 1000) {
        throw new HttpsError("invalid-argument", "meeting duration must be between 15 minutes and 8 hours.");
    }
    if (startTime.getTime() < Date.now() - 5 * 60 * 1000) {
        throw new HttpsError("invalid-argument", "startTime cannot be in the past.");
    }

    const privacyLevel = data.privacyLevel === "church" || data.privacyLevel === "organization" || data.privacyLevel === "space"
        ? data.privacyLevel
        : "private";

    const rawParticipants = Array.isArray(data.participants) ? data.participants : [];
    const participants = rawParticipants.slice(0, 100).map((item) => {
        const participant = item as Record<string, unknown>;
        return {
            userId: typeof participant.userId === "string" ? participant.userId : undefined,
            email: typeof participant.email === "string" ? participant.email : undefined,
            displayName: typeof participant.displayName === "string" ? participant.displayName.slice(0, 120) : undefined,
            role: participant.role === "host" ? "host" as const : "attendee" as const,
        };
    });

    return {
        title,
        description: typeof data.description === "string" ? data.description.slice(0, 2000) : undefined,
        agenda: typeof data.agenda === "string" ? data.agenda.slice(0, 4000) : undefined,
        scriptureFocus: typeof data.scriptureFocus === "string" ? data.scriptureFocus.slice(0, 500) : undefined,
        startTime,
        endTime,
        participants,
        amenSpaceId: typeof data.amenSpaceId === "string" ? data.amenSpaceId : undefined,
        organizationId: typeof data.organizationId === "string" ? data.organizationId : undefined,
        privacyLevel,
    };
}

export async function createMeetingWithProvider(input: {
    uid: string;
    provider: AmenIntegrationProvider;
    accountId: string;
    requestId: string;
    data: Record<string, unknown>;
}): Promise<{meetingId: string; meetingUrl: string; providerMeetingId: string; idempotent: boolean}> {
    if (!/^[A-Za-z0-9_-]{8,80}$/.test(input.requestId)) {
        throw new HttpsError("invalid-argument", "requestId is required for idempotency.");
    }

    const idempotencyRef = db.collection("amenIntegrationIdempotency").doc(`${input.uid}_${input.requestId}`);
    const existing = await idempotencyRef.get();
    if (existing.exists) {
        const data = existing.data() ?? {};
        return {
            meetingId: String(data.meetingId),
            meetingUrl: String(data.meetingUrl),
            providerMeetingId: String(data.providerMeetingId),
            idempotent: true,
        };
    }

    const meetingInput = validateMeetingInput(input.data);
    const tokenData = await getDecryptedIntegrationTokens(input.accountId, input.uid);
    if (tokenData.account.provider !== input.provider) {
        throw new HttpsError("failed-precondition", "Integration account provider mismatch.");
    }

    const adapter = getProviderAdapter(input.provider);
    const result = await adapter.createMeeting(tokenData.accessToken, meetingInput);
    const meetingRef = db.collection("amenMeetings").doc();
    const meeting: AmenMeeting = {
        provider: input.provider,
        providerMeetingId: result.providerMeetingId,
        meetingUrl: result.meetingUrl,
        title: meetingInput.title,
        description: meetingInput.description,
        agenda: meetingInput.agenda,
        scriptureFocus: meetingInput.scriptureFocus,
        startTime: admin.firestore.Timestamp.fromDate(meetingInput.startTime),
        endTime: admin.firestore.Timestamp.fromDate(meetingInput.endTime),
        createdBy: input.uid,
        amenSpaceId: meetingInput.amenSpaceId,
        organizationId: meetingInput.organizationId,
        privacyLevel: meetingInput.privacyLevel,
        participants: meetingInput.participants,
        followUpStatus: "not_started",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.runTransaction(async (tx) => {
        const idem = await tx.get(idempotencyRef);
        if (idem.exists) return;
        tx.set(meetingRef, meeting);
        tx.set(idempotencyRef, {
            uid: input.uid,
            requestId: input.requestId,
            meetingId: meetingRef.id,
            meetingUrl: result.meetingUrl,
            providerMeetingId: result.providerMeetingId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    });

    return {
        meetingId: meetingRef.id,
        meetingUrl: result.meetingUrl,
        providerMeetingId: result.providerMeetingId,
        idempotent: false,
    };
}
