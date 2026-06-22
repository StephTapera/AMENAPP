import * as functions from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = admin.firestore();
const auth = admin.auth();

const USERNAME_REGEX = /^[a-z0-9_]{3,20}$/;
type CallableAuthContext = {
    auth?: { uid: string };
    app?: unknown;
};
const RESERVED_USERNAMES = new Set([
    "admin",
    "amen",
    "support",
    "help",
    "moderator",
    "root",
    "system",
    "security",
    "delete",
    "deleted",
    "anonymous",
]);

function requireAppAuth(context: CallableAuthContext): string {
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (context.app == undefined) {
        throw new HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }
    return context.auth.uid;
}

function cleanUsername(value: unknown): string {
    const username = typeof value === "string" ? value.trim().toLowerCase() : "";
    if (!USERNAME_REGEX.test(username) || RESERVED_USERNAMES.has(username)) {
        throw new HttpsError("invalid-argument", "Choose a different username.");
    }
    return username;
}

function cleanDisplayName(value: unknown): string {
    const displayName = typeof value === "string" ? value.trim() : "";
    if (displayName.length === 0 || displayName.length > 100) {
        throw new HttpsError("invalid-argument", "Display name is required.");
    }
    return displayName;
}

function initialsFor(displayName: string): string {
    return displayName
        .split(/\s+/)
        .filter(Boolean)
        .slice(0, 2)
        .map((part) => part[0]?.toUpperCase() ?? "")
        .join("");
}

function nameKeywords(displayName: string): string[] {
    const normalized = displayName.toLowerCase().replace(/[^a-z0-9\s]/g, " ");
    const parts = normalized.split(/\s+/).filter((part) => part.length > 0);
    return Array.from(new Set(parts.flatMap((part) => {
        const keys: string[] = [];
        for (let i = 1; i <= Math.min(part.length, 20); i += 1) {
            keys.push(part.slice(0, i));
        }
        return keys;
    }))).slice(0, 80);
}

export const createAmenUserProfile = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAppAuth(context);
    const username = cleanUsername(data?.username);
    const displayName = cleanDisplayName(data?.displayName);
    const userRecord = await auth.getUser(uid);
    const email = userRecord.email ?? (typeof data?.email === "string" ? data.email.trim() : "");

    const userRef = db.collection("users").doc(uid);
    const lookupRef = db.collection("usernameLookup").doc(username);
    const privacyRef = db.collection("user_privacy_settings").doc(uid);

    await db.runTransaction(async (tx) => {
        const [userSnap, lookupSnap] = await Promise.all([
            tx.get(userRef),
            tx.get(lookupRef),
        ]);

        if (userSnap.exists) {
            throw new HttpsError("already-exists", "User profile already exists.");
        }
        if (lookupSnap.exists && lookupSnap.data()?.uid !== uid) {
            throw new HttpsError("already-exists", "Username is already taken.");
        }

        const serverTimestamp = admin.firestore.FieldValue.serverTimestamp();
        tx.set(userRef, {
            uid,
            email,
            displayName,
            displayNameLowercase: displayName.toLowerCase(),
            username,
            usernameLowercase: username,
            initials: initialsFor(displayName),
            bio: "",
            profileImageURL: null,
            nameKeywords: nameKeywords(displayName),
            createdAt: serverTimestamp,
            updatedAt: serverTimestamp,
            followersCount: 0,
            followingCount: 0,
            postsCount: 0,
            isPrivate: false,
            notificationsEnabled: true,
            pushNotificationsEnabled: true,
            emailNotificationsEnabled: true,
            notifyOnLikes: true,
            notifyOnComments: true,
            notifyOnFollows: true,
            notifyOnMentions: true,
            notifyOnPrayerRequests: true,
            allowMessagesFromEveryone: true,
            showActivityStatus: true,
            allowTagging: true,
            hasCompletedOnboarding: false,
            onboardingStatus: "incomplete",
            accountStatus: "active",
            deletionStatus: "none",
            twoFactorEnabled: false,
            schemaVersion: 2,
        });

        tx.set(lookupRef, {
            uid,
            username,
            usernameLowercase: username,
            createdAt: serverTimestamp,
        });

        tx.set(privacyRef, {
            userId: uid,
            profileVisibility: "friends",
            messagePermission: "followers",
            activityStatusVisible: false,
            aiPersonalizationEnabled: false,
            updatedAt: serverTimestamp,
        });
    });

    functions.logger.info("[createAmenUserProfile] profile created", { uid });
    return { success: true, uid, username };
});

export const deactivateAccount = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAppAuth(context);
    const reason = typeof data?.reason === "string" ? data.reason.slice(0, 80) : "user_requested";
    await db.collection("users").doc(uid).set({
        accountStatus: "deactivated",
        isDeactivated: true,
        deactivatedAt: admin.firestore.FieldValue.serverTimestamp(),
        deactivationReason: reason,
    }, { merge: true });
    await auth.setCustomUserClaims(uid, {
        ...(await auth.getUser(uid)).customClaims,
        deactivated: true,
    });
    return { success: true };
});

export const reactivateAccount = onCall({ enforceAppCheck: true }, async (request) => {
    const _data = request.data as any;
    const data = _data;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAppAuth(context);
    await db.collection("users").doc(uid).set({
        accountStatus: "active",
        isDeactivated: false,
        reactivatedAt: admin.firestore.FieldValue.serverTimestamp(),
        deactivatedAt: admin.firestore.FieldValue.delete(),
        deactivationReason: admin.firestore.FieldValue.delete(),
    }, { merge: true });
    await auth.setCustomUserClaims(uid, {
        ...(await auth.getUser(uid)).customClaims,
        deactivated: false,
    });
    return { success: true };
});

export const requestAccountDeletion = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAppAuth(context);
    const reason = typeof data?.reason === "string" ? data.reason.slice(0, 120) : "user_requested";
    const requestRef = db.collection("deletionRequests").doc(uid);
    await db.runTransaction(async (tx) => {
        tx.set(db.collection("users").doc(uid), {
            accountStatus: "deleting",
            deletionStatus: "requested",
            isDeleting: true,
            deletionRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        tx.set(requestRef, {
            userId: uid,
            reason,
            status: "requested",
            requestedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
    return { success: true, requestId: requestRef.id, status: "requested" };
});

export const checkPhoneVerificationRateLimit = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const uid = requireAppAuth({ auth: request.auth, app: request.app });
    const phoneNumber = typeof data?.phoneNumber === "string" ? data.phoneNumber.trim() : "";
    if (!phoneNumber) {
        throw new HttpsError("invalid-argument", "phoneNumber is required.");
    }

    const windowStart = admin.firestore.Timestamp.fromMillis(Date.now() - 15 * 60 * 1000);
    const recentFailures = await db
        .collection("phoneVerificationFailures")
        .where("uid", "==", uid)
        .where("phoneNumber", "==", phoneNumber)
        .where("createdAt", ">", windowStart)
        .get();
    const attempts = recentFailures.size ?? recentFailures.docs?.length ?? 0;
    const remainingAttempts = Math.max(0, 5 - attempts);

    return {
        allowed: remainingAttempts > 0,
        attempts,
        remainingAttempts,
        retryAfterSeconds: remainingAttempts > 0 ? 0 : 15 * 60,
    };
});

export const reportPhoneVerificationFailure = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const uid = requireAppAuth({ auth: request.auth, app: request.app });
    const phoneNumber = typeof data?.phoneNumber === "string" ? data.phoneNumber.trim() : "";
    const reason = typeof data?.reason === "string" ? data.reason.slice(0, 120) : "verification_failed";
    if (!phoneNumber) {
        throw new HttpsError("invalid-argument", "phoneNumber is required.");
    }

    const ref = db.collection("phoneVerificationFailures").doc();
    await ref.set({
        uid,
        phoneNumber,
        reason,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, failureId: ref.id };
});
