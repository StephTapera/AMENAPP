import * as functions from "firebase-functions";

export interface CreatorSpacesStorageObject {
    name?: string;
    contentType?: string;
    size?: string | number;
}

const MAX_CREATOR_SPACE_UPLOAD_BYTES = 500 * 1024 * 1024;
const ALLOWED_CREATOR_SPACE_CONTENT_TYPES = new Set([
    "image/jpeg",
    "image/png",
    "video/mp4",
    "audio/mp4",
    "audio/m4a",
    "audio/aac",
]);

export function assertCreatorSpaceStoragePath(storagePath: string, uid: string): void {
    const prefix = `creator_spaces/${uid}/`;
    if (!storagePath.startsWith(prefix) || storagePath.includes("..") || storagePath.includes("//")) {
        throw new functions.https.HttpsError("permission-denied", "Media path must belong to the authenticated user.");
    }
}

export function validateCreatorSpacesStorageObject(object: CreatorSpacesStorageObject): {
    ok: boolean;
    reason?: string;
} {
    const name = object.name ?? "";
    if (!name.startsWith("creator_spaces/") || name.includes("..") || name.includes("//")) {
        return { ok: false, reason: "invalid_path" };
    }

    const contentType = object.contentType ?? "";
    if (!ALLOWED_CREATOR_SPACE_CONTENT_TYPES.has(contentType)) {
        return { ok: false, reason: "invalid_content_type" };
    }

    const size = Number(object.size ?? 0);
    if (!Number.isFinite(size) || size <= 0 || size > MAX_CREATOR_SPACE_UPLOAD_BYTES) {
        return { ok: false, reason: "invalid_size" };
    }

    return { ok: true };
}

export function creatorSpaceEntitlementId(uid: string, spaceId: string, listingId: string): string {
    return `${uid}_${spaceId}_${listingId}`;
}
