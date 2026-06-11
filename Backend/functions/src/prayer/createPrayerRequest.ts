import * as admin from "firebase-admin";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";
import * as crypto from "crypto";

const prayerIdentityEncryptionKey = defineSecret("PRAYER_IDENTITY_ENCRYPTION_KEY");

const VALID_PRIVACY = new Set(["private", "trustedCircle", "church", "space", "public", "anonymous"]);

function readString(value: unknown, field: string, maxLength: number): string {
    if (typeof value !== "string") {
        throw new HttpsError("invalid-argument", `${field} is required.`);
    }
    const trimmed = value.trim();
    if (!trimmed || trimmed.length > maxLength) {
        throw new HttpsError("invalid-argument", `${field} must be 1-${maxLength} characters.`);
    }
    return trimmed;
}

function optionalString(value: unknown, field: string, maxLength: number): string | null {
    if (value == null) {
        return null;
    }
    if (typeof value !== "string") {
        throw new HttpsError("invalid-argument", `${field} must be a string.`);
    }
    const trimmed = value.trim();
    if (!trimmed) {
        return null;
    }
    if (trimmed.length > maxLength) {
        throw new HttpsError("invalid-argument", `${field} must be ${maxLength} characters or fewer.`);
    }
    return trimmed;
}

function readTags(value: unknown): string[] {
    if (!Array.isArray(value)) {
        return [];
    }
    return value
        .filter((tag): tag is string => typeof tag === "string")
        .map((tag) => tag.trim().toLowerCase())
        .filter(Boolean)
        .slice(0, 8);
}

function encryptionKey(): Buffer {
    const raw = prayerIdentityEncryptionKey.value();
    if (!raw) {
        throw new HttpsError("failed-precondition", "Prayer identity encryption is not configured.");
    }
    if (/^[A-Fa-f0-9]{64}$/.test(raw)) {
        return Buffer.from(raw, "hex");
    }
    try {
        const decoded = Buffer.from(raw, "base64");
        if (decoded.length === 32) {
            return decoded;
        }
    } catch {
        // Fall through to a stable key derivation for operator-provided passphrases.
    }
    return crypto.createHash("sha256").update(raw).digest();
}

function encryptOwnerUid(uid: string): string {
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv("aes-256-gcm", encryptionKey(), iv);
    const ciphertext = Buffer.concat([cipher.update(uid, "utf8"), cipher.final()]);
    const tag = cipher.getAuthTag();
    return [
        "v1",
        iv.toString("base64url"),
        tag.toString("base64url"),
        ciphertext.toString("base64url"),
    ].join(".");
}

export const createPrayerRequest = onCall(
    {
        enforceAppCheck: true,
        region: "us-central1",
        secrets: [prayerIdentityEncryptionKey],
        timeoutSeconds: 20,
    },
    async (request) => {
        const uid = request.auth?.uid;
        if (!uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }

        await enforceRateLimit(uid, [
            RATE_LIMITS.COMMUNITY_SAVE_PER_MINUTE,
            RATE_LIMITS.COMMUNITY_SAVE_PER_DAY,
        ]);

        const title = readString(request.data?.title, "title", 120);
        const body = readString(request.data?.body, "body", 2000);
        const privacyLevel = readString(request.data?.privacyLevel, "privacyLevel", 32);
        if (!VALID_PRIVACY.has(privacyLevel)) {
            throw new HttpsError("invalid-argument", "Invalid privacyLevel.");
        }

        const isAnonymous = request.data?.isAnonymous === true || privacyLevel === "anonymous";
        const churchRef = isAnonymous ? null : optionalString(request.data?.churchRef, "churchRef", 160);
        const spaceRef = isAnonymous ? null : optionalString(request.data?.spaceRef, "spaceRef", 160);
        const tags = readTags(request.data?.tags);
        const provenance = request.data?.provenance && typeof request.data.provenance === "object"
            ? request.data.provenance
            : null;

        const db = admin.firestore();
        const docRef = db.collection("prayers").doc();
        const projectionRef = db.collection("prayerRequests").doc(docRef.id);
        const now = admin.firestore.FieldValue.serverTimestamp();
        const authorName = isAnonymous ? "Anonymous" : optionalString(request.data?.displayAuthorName, "displayAuthorName", 120) ?? "";

        const prayerPayload: FirebaseFirestore.DocumentData = {
            id: docRef.id,
            _type: "prayer",
            title,
            body,
            privacyLevel: isAnonymous ? "anonymous" : privacyLevel,
            isAnonymous,
            displayAuthorName: authorName,
            tags,
            prayerCount: 0,
            followUps: [],
            isAnswered: false,
            reminderScheduled: false,
            createdBy: uid,
            ownerUid: uid,
            createdAt: now,
            updatedAt: now,
            isDeleted: false,
        };

        if (churchRef) {
            prayerPayload.churchRef = churchRef;
        }
        if (spaceRef) {
            prayerPayload.spaceRef = spaceRef;
        }
        if (isAnonymous) {
            prayerPayload.ownerUidEncrypted = encryptOwnerUid(uid);
        }
        if (provenance) {
            prayerPayload.provenance = provenance;
        }

        await db.runTransaction(async (tx) => {
            tx.set(docRef, prayerPayload);
            tx.set(projectionRef, {
                requesterUid: uid,
                requesterName: authorName || "Anonymous",
                title,
                prayingCount: 0,
                encouragementCount: 0,
                isAnswered: false,
                lastUpdated: now,
                pushToStartEnabled: true,
                sourcePrayerId: docRef.id,
            });
        });

        return {
            prayerId: docRef.id,
            projectionId: projectionRef.id,
            smartSuggestions: [
                { id: "pray-later", title: "Set a gentle reminder", intent: "remind" },
                { id: "invite-trusted", title: "Invite a trusted prayer partner", intent: "invite" },
            ],
        };
    }
);
