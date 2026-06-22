import { getFirestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";

const db = getFirestore();

export async function requireAmbientOSEnabled(): Promise<void> {
    const snap = await db.collection("serverFeatureFlags").doc("ambientOS").get();
    const enabled = snap.exists && snap.data()?.enabled === true;
    if (!enabled) {
        throw new HttpsError("failed-precondition", "Ambient OS is disabled.");
    }
}

export async function enforceAmbientContextRateLimit(uid: string): Promise<void> {
    await enforceRateLimit(uid, [
        RATE_LIMITS.SUGGEST_PER_MINUTE,
        RATE_LIMITS.SUGGEST_PER_DAY,
    ]);
}

export async function enforceAmbientAIRateLimit(uid: string): Promise<void> {
    await enforceRateLimit(uid, [
        RATE_LIMITS.AI_PER_MINUTE,
        RATE_LIMITS.AI_PER_DAY,
    ]);
}
