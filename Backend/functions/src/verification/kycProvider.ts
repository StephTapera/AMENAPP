/**
 * kycProvider.ts
 *
 * KYC provider abstraction for the Amen Verification & Trust System.
 *
 * Provider selection: set the KYC_PROVIDER env var to "persona" (default), "stripe", or "mock".
 * API credentials are read from Firebase environment config or process.env — never hardcoded.
 *
 * Privacy invariants:
 *   - Raw identity documents are NEVER stored by Amen.
 *   - Only the provider's reference ID (a non-decodable opaque token) is retained.
 *   - Webhook payloads are verified with HMAC before processing.
 *
 * Adding a new provider:
 *   1. Implement the KYCProvider interface.
 *   2. Add a case to getKYCProvider().
 *   3. Map your webhook event types in fromProviderEvent().
 */

import * as functions from "firebase-functions";
import * as crypto from "crypto";
import * as https from "https";

// ─── Types ────────────────────────────────────────────────────────────────────

export interface KYCSessionResult {
    /** Opaque session identifier returned to the iOS client. */
    sessionToken: string;
    /** SHA-256 hash of sessionToken stored server-side for matching. */
    sessionTokenHash: string;
    /** The provider-hosted URL the client opens in SFSafariViewController. */
    sessionUrl: string;
    /** Unix ms when the session expires. */
    expiresAt: number;
    /** Which provider created this session. */
    provider: KYCProviderName;
    /** Provider's own reference ID for the inquiry (stored after approval). */
    providerInquiryId?: string;
}

export interface KYCWebhookDecision {
    /** Normalised decision: "approved" | "rejected" | "needs_review" */
    event: "approved" | "rejected" | "needs_review";
    /** Provider's opaque reference ID — stored in privateVerification, NEVER decoded. */
    providerReferenceId: string;
    /** Provider-reported risk score 0–100, lower is safer. */
    riskScore: number;
    /** ISO-3166-1 alpha-2 country code from the submitted document. */
    country: string;
    /** Document type tier: "basic" | "enhanced" | "comprehensive" */
    verificationLevel: string;
    /** Unix ms until the verification expires (provider-reported). */
    expiresAt: number;
    /** Amen UID of the user who initiated the inquiry. */
    uid: string;
    /** Amen verificationRequest document ID. */
    requestId: string;
}

export type KYCProviderName = "persona" | "stripe" | "mock";

export interface KYCProvider {
    readonly name: KYCProviderName;

    /**
     * Creates a new identity verification session for the given user.
     * Returns the session URL the iOS client opens in SFSafariViewController.
     */
    createSession(uid: string, requestId: string): Promise<{
        sessionUrl: string;
        providerInquiryId: string;
        expiresAt: number;
    }>;

    /**
     * Verifies an incoming webhook signature.
     * Throws if the signature is invalid — caller must return 401.
     */
    verifyWebhookSignature(
        rawBody: Buffer | string,
        headers: Record<string, string | string[] | undefined>
    ): void;

    /**
     * Parses the raw webhook body into a normalised KYCWebhookDecision.
     * Returns null for events that don't require action (e.g. "inquiry.started").
     */
    parseWebhookEvent(
        rawBody: unknown,
        headers: Record<string, string | string[] | undefined>
    ): KYCWebhookDecision | null;
}

// ─── Factory ──────────────────────────────────────────────────────────────────

export function getKYCProvider(): KYCProvider {
    const name = (process.env.KYC_PROVIDER || "persona") as KYCProviderName;
    switch (name) {
        case "persona":
            return new PersonaKYCProvider();
        case "stripe":
            return new StripeIdentityKYCProvider();
        case "mock":
            return new MockKYCProvider();
        default:
            throw new Error(`Unknown KYC provider: ${name}`);
    }
}

// ─── Persona provider ─────────────────────────────────────────────────────────

/**
 * Persona Identity (withpersona.com) integration.
 *
 * Required environment variables (set via firebase functions:config:set or .env):
 *   KYC_PERSONA_API_KEY       — Persona API key (from Persona dashboard → API keys)
 *   KYC_PERSONA_TEMPLATE_ID   — Persona inquiry template ID (e.g. "itmpl_...")
 *   KYC_PERSONA_WEBHOOK_SECRET — Persona webhook signing secret
 *
 * Persona docs:
 *   https://docs.withpersona.com/docs/quickstart-embedded-flow
 *   https://docs.withpersona.com/reference/create-an-inquiry
 */
class PersonaKYCProvider implements KYCProvider {
    readonly name: KYCProviderName = "persona";

    private get apiKey(): string {
        const key =
            (functions.config().kyc?.persona_api_key as string | undefined) ||
            process.env.KYC_PERSONA_API_KEY ||
            "";
        if (!key) throw new Error("KYC_PERSONA_API_KEY is not configured.");
        return key;
    }

    private get templateId(): string {
        const id =
            (functions.config().kyc?.persona_template_id as string | undefined) ||
            process.env.KYC_PERSONA_TEMPLATE_ID ||
            "";
        if (!id) throw new Error("KYC_PERSONA_TEMPLATE_ID is not configured.");
        return id;
    }

    private get webhookSecret(): string {
        const s =
            (functions.config().kyc?.persona_webhook_secret as string | undefined) ||
            process.env.KYC_PERSONA_WEBHOOK_SECRET ||
            "";
        if (!s) throw new Error("KYC_PERSONA_WEBHOOK_SECRET is not configured.");
        return s;
    }

    async createSession(uid: string, requestId: string): Promise<{
        sessionUrl: string;
        providerInquiryId: string;
        expiresAt: number;
    }> {
        const body = JSON.stringify({
            data: {
                type: "inquiry",
                attributes: {
                    "inquiry-template-id": this.templateId,
                    // Pass Amen's request context as Persona reference IDs so we can
                    // match the webhook back to the right Firestore document.
                    "reference-id": uid,
                    "external-id": requestId,
                },
            },
        });

        const responseText = await httpPost(
            "withpersona.com",
            "/api/v1/inquiries",
            {
                "Content-Type": "application/json",
                "Accept": "application/json",
                "Persona-Version": "2023-01-05",
                "Authorization": `Bearer ${this.apiKey}`,
            },
            body
        );

        const response = JSON.parse(responseText) as {
            data?: {
                id?: string;
                attributes?: {
                    "session-token"?: string;
                    "expired-at"?: string;
                };
            };
        };

        const inquiryId = response.data?.id;
        const sessionToken = response.data?.attributes?.["session-token"];
        const expiredAt = response.data?.attributes?.["expired-at"];

        if (!inquiryId || !sessionToken) {
            throw new Error("Persona API returned unexpected response shape.");
        }

        const expiresAt = expiredAt
            ? new Date(expiredAt).getTime()
            : Date.now() + 60 * 60 * 1000; // default 1 hour

        return {
            // Persona's hosted flow URL — client opens this in SFSafariViewController
            sessionUrl: `https://withpersona.com/verify?inquiry-id=${inquiryId}&session-token=${sessionToken}`,
            providerInquiryId: inquiryId,
            expiresAt,
        };
    }

    verifyWebhookSignature(
        rawBody: Buffer | string,
        headers: Record<string, string | string[] | undefined>
    ): void {
        const sig = (headers["persona-signature"] as string | undefined) || "";
        // Persona sends: t=<timestamp>,v1=<hmac>
        const parts = Object.fromEntries(
            sig.split(",").map((part) => part.split("=") as [string, string])
        );
        const timestamp = parts["t"];
        const v1 = parts["v1"];

        if (!timestamp || !v1) {
            throw new Error("Missing Persona webhook signature components.");
        }

        const payload =
            typeof rawBody === "string" ? rawBody : rawBody.toString("utf8");
        const expected = crypto
            .createHmac("sha256", this.webhookSecret)
            .update(`${timestamp}.${payload}`)
            .digest("hex");

        if (!crypto.timingSafeEqual(Buffer.from(v1, "hex"), Buffer.from(expected, "hex"))) {
            throw new Error("Invalid Persona webhook signature.");
        }
    }

    parseWebhookEvent(
        rawBody: unknown,
        _headers: Record<string, string | string[] | undefined>
    ): KYCWebhookDecision | null {
        const body = rawBody as {
            data?: {
                type?: string;
                attributes?: {
                    status?: string;
                    "reference-id"?: string; // Amen UID
                    "external-id"?: string;  // Amen requestId
                    payload?: {
                        data?: {
                            attributes?: {
                                "risk-score"?: number;
                                "country-code"?: string;
                                "inquiry-template-version-id"?: string;
                            };
                        };
                    };
                };
                id?: string;
            };
        };

        const eventType = body.data?.type;
        const status = body.data?.attributes?.status;

        // Only act on final decisions
        if (!eventType?.startsWith("inquiry")) return null;
        if (status !== "approved" && status !== "declined" && status !== "needs_review") {
            return null;
        }

        const attrs = body.data?.attributes;
        const uid = attrs?.["reference-id"] || "";
        const requestId = attrs?.["external-id"] || "";
        const providerReferenceId = body.data?.id || "";
        const riskScore = attrs?.payload?.data?.attributes?.["risk-score"] ?? 50;
        const country = attrs?.payload?.data?.attributes?.["country-code"] ?? "unknown";

        if (!uid || !requestId || !providerReferenceId) return null;

        return {
            event: status === "approved" ? "approved"
                 : status === "needs_review" ? "needs_review"
                 : "rejected",
            providerReferenceId,
            riskScore,
            country,
            verificationLevel: "enhanced",
            expiresAt: Date.now() + 365 * 24 * 60 * 60 * 1000, // 1 year default
            uid,
            requestId,
        };
    }
}

// ─── Stripe Identity provider ─────────────────────────────────────────────────

/**
 * Stripe Identity (stripe.com/identity) integration.
 *
 * Required environment variables:
 *   KYC_STRIPE_SECRET_KEY         — Stripe secret key (sk_live_... / sk_test_...)
 *   KYC_STRIPE_WEBHOOK_SECRET     — Stripe webhook endpoint signing secret (whsec_...)
 *
 * Stripe docs:
 *   https://stripe.com/docs/identity/verify-identity-documents
 */
class StripeIdentityKYCProvider implements KYCProvider {
    readonly name: KYCProviderName = "stripe";

    private get secretKey(): string {
        const key =
            (functions.config().kyc?.stripe_secret_key as string | undefined) ||
            process.env.KYC_STRIPE_SECRET_KEY ||
            "";
        if (!key) throw new Error("KYC_STRIPE_SECRET_KEY is not configured.");
        return key;
    }

    private get webhookSecret(): string {
        const s =
            (functions.config().kyc?.stripe_webhook_secret as string | undefined) ||
            process.env.KYC_STRIPE_WEBHOOK_SECRET ||
            "";
        if (!s) throw new Error("KYC_STRIPE_WEBHOOK_SECRET is not configured.");
        return s;
    }

    async createSession(uid: string, requestId: string): Promise<{
        sessionUrl: string;
        providerInquiryId: string;
        expiresAt: number;
    }> {
        const body = new URLSearchParams({
            "type": "document",
            "metadata[amen_uid]": uid,
            "metadata[amen_request_id]": requestId,
            "return_url": `https://amen.app/verification/complete?uid=${uid}&requestId=${requestId}`,
        }).toString();

        const responseText = await httpPost(
            "api.stripe.com",
            "/v1/identity/verification_sessions",
            {
                "Content-Type": "application/x-www-form-urlencoded",
                "Authorization": `Bearer ${this.secretKey}`,
            },
            body
        );

        const session = JSON.parse(responseText) as {
            id?: string;
            url?: string;
        };

        if (!session.id || !session.url) {
            throw new Error("Stripe Identity API returned unexpected response shape.");
        }

        return {
            sessionUrl: session.url,
            providerInquiryId: session.id,
            expiresAt: Date.now() + 48 * 60 * 60 * 1000, // Stripe sessions expire in 48 hours
        };
    }

    verifyWebhookSignature(
        rawBody: Buffer | string,
        headers: Record<string, string | string[] | undefined>
    ): void {
        const sig = (headers["stripe-signature"] as string | undefined) || "";
        const parts = Object.fromEntries(
            sig.split(",").map((p) => p.split("=") as [string, string])
        );
        const timestamp = parts["t"];
        const v1 = parts["v1"];
        if (!timestamp || !v1) throw new Error("Missing Stripe webhook signature.");

        const payload = typeof rawBody === "string" ? rawBody : rawBody.toString("utf8");
        const expected = crypto
            .createHmac("sha256", this.webhookSecret)
            .update(`${timestamp}.${payload}`)
            .digest("hex");

        if (!crypto.timingSafeEqual(Buffer.from(v1, "hex"), Buffer.from(expected, "hex"))) {
            throw new Error("Invalid Stripe webhook signature.");
        }
    }

    parseWebhookEvent(
        rawBody: unknown,
        _headers: Record<string, string | string[] | undefined>
    ): KYCWebhookDecision | null {
        const event = rawBody as {
            type?: string;
            data?: {
                object?: {
                    id?: string;
                    status?: string;
                    last_error?: { code?: string };
                    metadata?: { amen_uid?: string; amen_request_id?: string };
                    risk_insights?: { clarifications?: string[] };
                };
            };
        };

        if (event.type !== "identity.verification_session.verified" &&
            event.type !== "identity.verification_session.requires_input") {
            return null;
        }

        const obj = event.data?.object;
        const uid = obj?.metadata?.amen_uid || "";
        const requestId = obj?.metadata?.amen_request_id || "";
        const providerReferenceId = obj?.id || "";

        if (!uid || !requestId || !providerReferenceId) return null;

        const verified = event.type === "identity.verification_session.verified";

        return {
            event: verified ? "approved" : "needs_review",
            providerReferenceId,
            riskScore: verified ? 10 : 70,
            country: "unknown",
            verificationLevel: "enhanced",
            expiresAt: Date.now() + 365 * 24 * 60 * 60 * 1000,
            uid,
            requestId,
        };
    }
}

// ─── Mock provider (test / staging only) ─────────────────────────────────────

export class MockKYCProvider implements KYCProvider {
    readonly name: KYCProviderName = "mock";

    async createSession(uid: string, requestId: string): Promise<{
        sessionUrl: string;
        providerInquiryId: string;
        expiresAt: number;
    }> {
        return {
            sessionUrl: `https://verify.amen.app/mock-session?uid=${uid}&requestId=${requestId}`,
            providerInquiryId: `mock_inquiry_${requestId}`,
            expiresAt: Date.now() + 60 * 60 * 1000,
        };
    }

    verifyWebhookSignature(
        rawBody: Buffer | string,
        headers: Record<string, string | string[] | undefined>
    ): void {
        const sig = headers["x-amen-webhook-signature"] as string | undefined;
        const secret = process.env.WEBHOOK_SECRET || "mock-secret";
        const payload = typeof rawBody === "string" ? rawBody : rawBody.toString("utf8");
        const expected = crypto.createHmac("sha256", secret).update(payload).digest("hex");
        if (sig !== expected) throw new Error("Invalid mock webhook signature.");
    }

    parseWebhookEvent(
        rawBody: unknown,
        _headers: Record<string, string | string[] | undefined>
    ): KYCWebhookDecision | null {
        return rawBody as KYCWebhookDecision | null;
    }
}

// ─── HTTP helper (no external deps) ──────────────────────────────────────────

function httpPost(
    hostname: string,
    path: string,
    headers: Record<string, string>,
    body: string
): Promise<string> {
    return new Promise((resolve, reject) => {
        const req = https.request(
            {
                hostname,
                path,
                method: "POST",
                headers: {
                    ...headers,
                    "Content-Length": Buffer.byteLength(body),
                },
            },
            (res) => {
                let data = "";
                res.on("data", (chunk: Buffer) => { data += chunk.toString(); });
                res.on("end", () => {
                    if (res.statusCode && res.statusCode >= 400) {
                        reject(new Error(`HTTP ${res.statusCode}: ${data}`));
                    } else {
                        resolve(data);
                    }
                });
            }
        );
        req.on("error", reject);
        req.write(body);
        req.end();
    });
}
