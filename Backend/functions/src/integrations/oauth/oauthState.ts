import * as crypto from "crypto";
import * as admin from "firebase-admin";
import type {AmenIntegrationProvider} from "../models";

const db = admin.firestore();
const STATE_TTL_MS = 10 * 60 * 1000;

export function hashOAuthState(state: string): string {
    return crypto.createHash("sha256").update(state).digest("hex");
}

export function createOAuthStateValue(): string {
    return crypto.randomBytes(32).toString("base64url");
}

export function integrationOAuthRedirectUri(): string {
    return process.env.INTEGRATION_OAUTH_REDIRECT_URI ??
        "https://us-central1-amen-5e359.cloudfunctions.net/amenIntegrationOAuthCallback";
}

export async function storeOAuthState(input: {
    uid: string;
    provider: AmenIntegrationProvider;
    state: string;
    organizationId?: string;
}): Promise<void> {
    await db.collection("amenIntegrationOAuthStates").doc(hashOAuthState(input.state)).set({
        uid: input.uid,
        provider: input.provider,
        organizationId: input.organizationId ?? null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAtMillis: Date.now() + STATE_TTL_MS,
        usedAt: null,
    });
}

export async function consumeOAuthState(state: string, provider: AmenIntegrationProvider): Promise<{
    uid: string;
    organizationId?: string;
}> {
    const ref = db.collection("amenIntegrationOAuthStates").doc(hashOAuthState(state));
    return db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) throw new Error("oauth_state_not_found");
        const data = snap.data() ?? {};
        if (data.provider !== provider) throw new Error("oauth_state_provider_mismatch");
        if (data.usedAt) throw new Error("oauth_state_replayed");
        if (Number(data.expiresAtMillis ?? 0) < Date.now()) throw new Error("oauth_state_expired");

        tx.update(ref, {
            usedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return {
            uid: String(data.uid),
            organizationId: typeof data.organizationId === "string" ? data.organizationId : undefined,
        };
    });
}
