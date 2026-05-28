#!/usr/bin/env node
/*
 * Live KYC provider smoke test for Amen Verification & Trust.
 *
 * This intentionally does not use mocked Firebase tests. It creates a real
 * provider-hosted identity session and validates webhook signature rejection
 * against the deployed webhook URL. It does not submit ID documents.
 *
 * Required env:
 *   KYC_PROVIDER=persona|stripe
 *   AMEN_KYC_WEBHOOK_URL=https://.../handleIdentityVerificationWebhook
 *
 * Persona:
 *   KYC_PERSONA_API_KEY=...
 *   KYC_PERSONA_TEMPLATE_ID=...
 *
 * Stripe:
 *   KYC_STRIPE_SECRET_KEY=...
 *
 * Optional:
 *   AMEN_SMOKE_UID=verification-smoke-uid
 *   AMEN_SMOKE_REQUEST_ID=verification-smoke-request
 */

import https from "node:https";

const provider = process.env.KYC_PROVIDER;
const uid = process.env.AMEN_SMOKE_UID || `verification-smoke-${Date.now()}`;
const requestId = process.env.AMEN_SMOKE_REQUEST_ID || `smoke-${Date.now()}`;
const webhookUrl = process.env.AMEN_KYC_WEBHOOK_URL;

function requireEnv(name) {
    const value = process.env[name];
    if (!value) {
        throw new Error(`${name} is required.`);
    }
    return value;
}

function post(hostname, path, headers, body) {
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
                res.on("data", (chunk) => { data += chunk.toString(); });
                res.on("end", () => {
                    if (res.statusCode >= 400) {
                        reject(new Error(`HTTP ${res.statusCode}: ${data}`));
                        return;
                    }
                    resolve({ statusCode: res.statusCode, body: data });
                });
            }
        );
        req.on("error", reject);
        req.write(body);
        req.end();
    });
}

async function createPersonaSession() {
    const apiKey = requireEnv("KYC_PERSONA_API_KEY");
    const templateId = requireEnv("KYC_PERSONA_TEMPLATE_ID");
    const body = JSON.stringify({
        data: {
            type: "inquiry",
            attributes: {
                "inquiry-template-id": templateId,
                "reference-id": uid,
                "external-id": requestId,
            },
        },
    });

    const response = await post(
        "withpersona.com",
        "/api/v1/inquiries",
        {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Persona-Version": "2023-01-05",
            "Authorization": `Bearer ${apiKey}`,
        },
        body
    );

    const parsed = JSON.parse(response.body);
    const inquiryId = parsed?.data?.id;
    const sessionToken = parsed?.data?.attributes?.["session-token"];
    if (!inquiryId || !sessionToken) {
        throw new Error("Persona response did not include inquiry id and session token.");
    }

    return {
        providerReferenceId: inquiryId,
        sessionUrl: `https://withpersona.com/verify?inquiry-id=${inquiryId}&session-token=${sessionToken}`,
    };
}

async function createStripeSession() {
    const secretKey = requireEnv("KYC_STRIPE_SECRET_KEY");
    const body = new URLSearchParams({
        "type": "document",
        "metadata[amen_uid]": uid,
        "metadata[amen_request_id]": requestId,
        "return_url": `https://amen.app/verification/complete?uid=${uid}&requestId=${requestId}`,
    }).toString();

    const response = await post(
        "api.stripe.com",
        "/v1/identity/verification_sessions",
        {
            "Content-Type": "application/x-www-form-urlencoded",
            "Authorization": `Bearer ${secretKey}`,
        },
        body
    );

    const parsed = JSON.parse(response.body);
    if (!parsed?.id || !parsed?.url) {
        throw new Error("Stripe response did not include verification session id and url.");
    }

    return {
        providerReferenceId: parsed.id,
        sessionUrl: parsed.url,
    };
}

async function assertWebhookRejectsUnsignedPayload() {
    if (!webhookUrl) {
        console.warn("WARN: AMEN_KYC_WEBHOOK_URL not set; skipping deployed webhook rejection check.");
        return;
    }

    const url = new URL(webhookUrl);
    const response = await new Promise((resolve, reject) => {
        const body = JSON.stringify({ smoke: true });
        const req = https.request(
            {
                hostname: url.hostname,
                path: `${url.pathname}${url.search}`,
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "Content-Length": Buffer.byteLength(body),
                },
            },
            (res) => {
                res.resume();
                res.on("end", () => resolve(res.statusCode));
            }
        );
        req.on("error", reject);
        req.write(body);
        req.end();
    });

    if (response !== 401) {
        throw new Error(`Expected unsigned webhook request to be rejected with 401, got ${response}.`);
    }
}

async function main() {
    if (provider !== "persona" && provider !== "stripe") {
        throw new Error("KYC_PROVIDER must be 'persona' or 'stripe' for live smoke tests.");
    }

    console.log(`Running live ${provider} KYC smoke test`);
    console.log(`Amen UID: ${uid}`);
    console.log(`Amen requestId: ${requestId}`);

    const session = provider === "persona"
        ? await createPersonaSession()
        : await createStripeSession();

    if (!session.sessionUrl.startsWith("https://")) {
        throw new Error("Provider returned a non-HTTPS session URL.");
    }

    await assertWebhookRejectsUnsignedPayload();

    console.log("PASS: provider session created");
    console.log(`Provider reference: ${session.providerReferenceId}`);
    console.log(`Session URL: ${session.sessionUrl}`);
    console.log("NEXT: open the session URL, complete provider sandbox approval/rejection, then confirm webhook updates Firestore.");
}

main().catch((error) => {
    console.error(`FAIL: ${error.message}`);
    process.exit(1);
});
