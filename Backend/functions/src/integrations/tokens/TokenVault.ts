import * as crypto from "crypto";
import * as admin from "firebase-admin";
import type {AmenIntegrationAccount, AmenIntegrationProvider, EncryptedTokenEnvelope, OAuthTokenResponse} from "../models";

const db = admin.firestore();

function getKey(): Buffer {
    const raw = process.env.INTEGRATION_TOKEN_ENCRYPTION_KEY ?? "";
    const key = raw.startsWith("base64:")
        ? Buffer.from(raw.slice("base64:".length), "base64")
        : Buffer.from(raw, "utf8");

    if (key.length !== 32) {
        throw new Error("integration_token_key_invalid");
    }
    return key;
}

export function encryptToken(token: string): EncryptedTokenEnvelope {
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv("aes-256-gcm", getKey(), iv);
    const ciphertext = Buffer.concat([cipher.update(token, "utf8"), cipher.final()]);
    const authTag = cipher.getAuthTag();
    return {
        algorithm: "aes-256-gcm",
        keyVersion: "v1",
        iv: iv.toString("base64"),
        ciphertext: ciphertext.toString("base64"),
        authTag: authTag.toString("base64"),
    };
}

export function decryptToken(envelope: EncryptedTokenEnvelope): string {
    if (envelope.algorithm !== "aes-256-gcm") {
        throw new Error("unsupported_token_envelope");
    }
    const decipher = crypto.createDecipheriv(
        "aes-256-gcm",
        getKey(),
        Buffer.from(envelope.iv, "base64")
    );
    decipher.setAuthTag(Buffer.from(envelope.authTag, "base64"));
    return Buffer.concat([
        decipher.update(Buffer.from(envelope.ciphertext, "base64")),
        decipher.final(),
    ]).toString("utf8");
}

export function integrationAccountId(uid: string, provider: AmenIntegrationProvider, workspaceId?: string): string {
    const suffix = workspaceId ? crypto.createHash("sha256").update(workspaceId).digest("hex").slice(0, 16) : "default";
    return `${uid}_${provider}_${suffix}`;
}

export async function storeIntegrationTokens(input: {
    uid: string;
    provider: AmenIntegrationProvider;
    tokenResponse: OAuthTokenResponse;
}): Promise<string> {
    const accountId = integrationAccountId(input.uid, input.provider, input.tokenResponse.workspaceId);
    const now = admin.firestore.FieldValue.serverTimestamp();
    const expiresAt = input.tokenResponse.expiresIn
        ? admin.firestore.Timestamp.fromMillis(Date.now() + input.tokenResponse.expiresIn * 1000)
        : undefined;

    const account: AmenIntegrationAccount = {
        userId: input.uid,
        provider: input.provider,
        encryptedAccessToken: encryptToken(input.tokenResponse.accessToken),
        encryptedRefreshToken: input.tokenResponse.refreshToken ? encryptToken(input.tokenResponse.refreshToken) : undefined,
        scopes: input.tokenResponse.scopes,
        workspaceId: input.tokenResponse.workspaceId,
        workspaceName: input.tokenResponse.workspaceName,
        providerUserId: input.tokenResponse.providerUserId,
        connectedAt: now,
        expiresAt,
        revokedAt: null,
        status: "connected",
        updatedAt: now,
    };

    await db.collection("amenIntegrationAccounts").doc(accountId).set(account, {merge: true});
    return accountId;
}

export async function getDecryptedIntegrationTokens(accountId: string, uid: string): Promise<{
    accessToken: string;
    refreshToken?: string;
    account: FirebaseFirestore.DocumentData;
}> {
    const snap = await db.collection("amenIntegrationAccounts").doc(accountId).get();
    if (!snap.exists || snap.data()?.userId !== uid || snap.data()?.status !== "connected") {
        throw new Error("integration_account_unavailable");
    }
    const data = snap.data()!;
    return {
        accessToken: decryptToken(data.encryptedAccessToken as EncryptedTokenEnvelope),
        refreshToken: data.encryptedRefreshToken ? decryptToken(data.encryptedRefreshToken as EncryptedTokenEnvelope) : undefined,
        account: data,
    };
}
