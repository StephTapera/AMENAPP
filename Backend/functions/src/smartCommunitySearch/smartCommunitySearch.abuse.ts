import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

const db = admin.firestore();

export interface SmartSearchAbuseSignal {
    uid: string;
    appId?: string;
    safetyBlocked: boolean;
    crisisDetected: boolean;
}

function currentWindowId(windowMs: number): string {
    return String(Math.floor(Date.now() / windowMs) * windowMs);
}

export async function enforceSmartSearchAbuseLimit(input: SmartSearchAbuseSignal): Promise<void> {
    const windowMs = 60 * 60 * 1000;
    const appPart = input.appId ? `_${input.appId.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 64)}` : "";
    const ref = db
        .collection("smartSearchAbuseLimits")
        .doc(`${input.uid}${appPart}`)
        .collection("windows")
        .doc(currentWindowId(windowMs));

    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const data = snap.exists ? snap.data() as { blockedCount?: number; crisisCount?: number; totalCount?: number } : {};
        const blockedCount = data.blockedCount ?? 0;
        const crisisCount = data.crisisCount ?? 0;
        const totalCount = data.totalCount ?? 0;

        if (blockedCount >= 12 || totalCount >= 240) {
            throw new HttpsError("resource-exhausted", "Smart search is temporarily rate limited.");
        }

        tx.set(ref, {
            uid: input.uid,
            appId: input.appId ?? null,
            blockedCount: blockedCount + (input.safetyBlocked ? 1 : 0),
            crisisCount: crisisCount + (input.crisisDetected ? 1 : 0),
            totalCount: totalCount + 1,
            windowEnd: Date.now() + windowMs,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
}
