import * as admin from "firebase-admin";
import {defineSecret} from "firebase-functions/params";
import {HttpsError, onCall, onRequest} from "firebase-functions/v2/https";
import {enforceRateLimit, type RateLimitConfig} from "../rateLimit";
import type {AmenIntegrationProvider} from "./models";
import {writeIntegrationAudit} from "./audit/integrationAudit";
import {getAmenIntegrationFlags, providerEnabled} from "./featureFlags/integrationFlags";
import {createMeetingWithProvider} from "./meetings/meetingService";
import {consumeOAuthState, createOAuthStateValue, integrationOAuthRedirectUri, storeOAuthState} from "./oauth/oauthState";
import {assertProviderConfigured, getProviderAdapter} from "./providers/providerRegistry";
import {getDecryptedIntegrationTokens, storeIntegrationTokens} from "./tokens/TokenVault";

const microsoftClientId = defineSecret("MICROSOFT_GRAPH_CLIENT_ID");
const microsoftClientSecret = defineSecret("MICROSOFT_GRAPH_CLIENT_SECRET");
const zoomClientId = defineSecret("ZOOM_CLIENT_ID");
const zoomClientSecret = defineSecret("ZOOM_CLIENT_SECRET");
const slackClientId = defineSecret("SLACK_CLIENT_ID");
const slackClientSecret = defineSecret("SLACK_CLIENT_SECRET");
const tokenEncryptionKey = defineSecret("INTEGRATION_TOKEN_ENCRYPTION_KEY");

const integrationSecrets = [
    microsoftClientId,
    microsoftClientSecret,
    zoomClientId,
    zoomClientSecret,
    slackClientId,
    slackClientSecret,
    tokenEncryptionKey,
];

const INTEGRATION_PER_MINUTE: RateLimitConfig = {
    name: "amen_integrations_1min",
    windowMs: 60_000,
    maxCalls: 20,
};

const INTEGRATION_PER_DAY: RateLimitConfig = {
    name: "amen_integrations_1day",
    windowMs: 86_400_000,
    maxCalls: 100,
};

function parseProvider(value: unknown): AmenIntegrationProvider {
    if (value === "microsoft" || value === "zoom" || value === "slack") return value;
    throw new HttpsError("invalid-argument", "provider must be microsoft, zoom, or slack.");
}

async function assertIntegrationEnabled(provider: AmenIntegrationProvider): Promise<void> {
    const flags = await getAmenIntegrationFlags();
    if (!providerEnabled(flags, provider)) {
        throw new HttpsError("failed-precondition", `${provider} integration is disabled.`);
    }
}

export const startIntegrationOAuth = onCall(
    {secrets: integrationSecrets, enforceAppCheck: true, region: "us-central1"},
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Authentication required.");
        const provider = parseProvider(request.data?.provider);
        await enforceRateLimit(request.auth.uid, [INTEGRATION_PER_MINUTE, INTEGRATION_PER_DAY]);
        await assertIntegrationEnabled(provider);
        assertProviderConfigured(provider);

        const organizationId = typeof request.data?.organizationId === "string" ? request.data.organizationId : undefined;
        if (organizationId && !request.auth.token.admin) {
            throw new HttpsError("permission-denied", "Organization integrations require an admin account.");
        }

        const state = createOAuthStateValue();
        const redirectUri = integrationOAuthRedirectUri();
        await storeOAuthState({
            uid: request.auth.uid,
            provider,
            state,
            organizationId,
        });

        const adapter = getProviderAdapter(provider);
        const authorizationUrl = adapter.authorizationUrl(state, redirectUri);
        await writeIntegrationAudit({
            provider,
            action: "oauth_start",
            actorId: request.auth.uid,
            success: true,
            securityFlags: ["app_check", "state_created"],
            metadata: {organizationLinked: !!organizationId},
        });

        return {
            provider,
            authorizationUrl,
            expiresInSeconds: 600,
        };
    }
);

export const amenIntegrationOAuthCallback = onRequest(
    {secrets: integrationSecrets, region: "us-central1"},
    async (req, res) => {
        const provider = req.query.provider as AmenIntegrationProvider;
        const code = typeof req.query.code === "string" ? req.query.code : "";
        const state = typeof req.query.state === "string" ? req.query.state : "";
        const error = typeof req.query.error === "string" ? req.query.error : "";
        const redirect = (status: "success" | "error", reason?: string) => {
            res.redirect(302, `amen://integrations/oauth?provider=${encodeURIComponent(String(provider))}&status=${status}${reason ? `&reason=${encodeURIComponent(reason)}` : ""}`);
        };

        try {
            if (provider !== "microsoft" && provider !== "zoom" && provider !== "slack") {
                redirect("error", "invalid_provider");
                return;
            }
            if (error) {
                redirect("error", error);
                return;
            }
            if (!code || !state) {
                redirect("error", "missing_code_or_state");
                return;
            }

            await assertIntegrationEnabled(provider);
            assertProviderConfigured(provider);
            const stateData = await consumeOAuthState(state, provider);
            const adapter = getProviderAdapter(provider);
            const tokenResponse = await adapter.exchangeOAuthCode(code, integrationOAuthRedirectUri());
            const accountId = await storeIntegrationTokens({
                uid: stateData.uid,
                provider,
                tokenResponse,
            });
            await writeIntegrationAudit({
                provider,
                action: "oauth_callback",
                actorId: stateData.uid,
                success: true,
                securityFlags: ["state_verified", "tokens_encrypted"],
                metadata: {accountId, organizationLinked: !!stateData.organizationId},
            });
            redirect("success");
        } catch (err: unknown) {
            await writeIntegrationAudit({
                provider: provider === "microsoft" || provider === "zoom" || provider === "slack" ? provider : "microsoft",
                action: "oauth_callback",
                actorId: "unknown",
                success: false,
                errorCode: err instanceof Error ? err.message : "unknown",
                securityFlags: ["callback_failed"],
            }).catch(() => undefined);
            redirect("error", err instanceof Error ? err.message : "unknown");
        }
    }
);

export const getAmenIntegrationAccounts = onCall(
    {enforceAppCheck: true, region: "us-central1"},
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Authentication required.");
        const snap = await admin.firestore()
            .collection("amenIntegrationAccounts")
            .where("userId", "==", request.auth.uid)
            .get();

        return {
            accounts: snap.docs.map((doc) => {
                const data = doc.data();
                return {
                    id: doc.id,
                    provider: data.provider,
                    status: data.status,
                    scopes: data.scopes ?? [],
                    workspaceId: data.workspaceId ?? null,
                    workspaceName: data.workspaceName ?? null,
                    providerUserId: data.providerUserId ?? null,
                    expiresAtMillis: data.expiresAt?.toMillis?.() ?? null,
                    connectedAtMillis: data.connectedAt?.toMillis?.() ?? null,
                };
            }),
        };
    }
);

export const revokeAmenIntegrationAccount = onCall(
    {secrets: integrationSecrets, enforceAppCheck: true, region: "us-central1"},
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Authentication required.");
        const accountId = typeof request.data?.accountId === "string" ? request.data.accountId : "";
        if (!accountId) throw new HttpsError("invalid-argument", "accountId is required.");
        await enforceRateLimit(request.auth.uid, [INTEGRATION_PER_MINUTE, INTEGRATION_PER_DAY]);

        const tokenData = await getDecryptedIntegrationTokens(accountId, request.auth.uid);
        const provider = tokenData.account.provider as AmenIntegrationProvider;
        const adapter = getProviderAdapter(provider);
        await adapter.revokeToken(tokenData.accessToken, tokenData.refreshToken).catch(() => undefined);
        await admin.firestore().collection("amenIntegrationAccounts").doc(accountId).set({
            status: "revoked",
            revokedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        await writeIntegrationAudit({
            provider,
            action: "account_revoked",
            actorId: request.auth.uid,
            success: true,
            securityFlags: ["local_tokens_disabled"],
            metadata: {accountId},
        });
        return {ok: true};
    }
);

export const createAmenMeeting = onCall(
    {secrets: integrationSecrets, enforceAppCheck: true, region: "us-central1"},
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Authentication required.");
        const provider = parseProvider(request.data?.provider);
        await enforceRateLimit(request.auth.uid, [INTEGRATION_PER_MINUTE, INTEGRATION_PER_DAY]);
        const flags = await getAmenIntegrationFlags();
        if (!flags.meetingCreationEnabled) {
            throw new HttpsError("failed-precondition", "Meeting creation is disabled.");
        }
        await assertIntegrationEnabled(provider);
        if (provider === "slack") {
            throw new HttpsError("invalid-argument", "Slack does not create meetings.");
        }

        const accountId = typeof request.data?.accountId === "string" ? request.data.accountId : "";
        const requestId = typeof request.data?.requestId === "string" ? request.data.requestId : "";
        if (!accountId) throw new HttpsError("invalid-argument", "accountId is required.");

        const result = await createMeetingWithProvider({
            uid: request.auth.uid,
            provider,
            accountId,
            requestId,
            data: request.data ?? {},
        });

        await writeIntegrationAudit({
            provider,
            action: "meeting_created",
            actorId: request.auth.uid,
            success: true,
            securityFlags: ["callable_only", "idempotency_checked"],
            metadata: {meetingId: result.meetingId, idempotent: result.idempotent},
        });

        return result;
    }
);
