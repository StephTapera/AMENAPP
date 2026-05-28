import * as crypto from "crypto";
import {MicrosoftGraphProvider} from "./providers/MicrosoftGraphProvider";
import {SlackProvider, verifySlackSignature} from "./providers/SlackProvider";
import {ZoomProvider} from "./providers/ZoomProvider";
import {createOAuthStateValue, hashOAuthState} from "./oauth/oauthState";
import {decryptToken, encryptToken} from "./tokens/TokenVault";

describe("Amen Integrations Platform", () => {
    const originalKey = process.env.INTEGRATION_TOKEN_ENCRYPTION_KEY;

    beforeEach(() => {
        process.env.INTEGRATION_TOKEN_ENCRYPTION_KEY = "12345678901234567890123456789012";
    });

    afterEach(() => {
        process.env.INTEGRATION_TOKEN_ENCRYPTION_KEY = originalKey;
    });

    it("encrypts tokens without storing plaintext", () => {
        const encrypted = encryptToken("secret-access-token");

        expect(encrypted.ciphertext).not.toContain("secret-access-token");
        expect(decryptToken(encrypted)).toBe("secret-access-token");
    });

    it("creates high-entropy OAuth state values and stable hashes", () => {
        const state = createOAuthStateValue();

        expect(state.length).toBeGreaterThan(32);
        expect(hashOAuthState(state)).toBe(hashOAuthState(state));
        expect(hashOAuthState(state)).not.toBe(state);
    });

    it("builds Microsoft authorization URLs with minimal meeting/calendar scopes", () => {
        const provider = new MicrosoftGraphProvider("client-id", "client-secret");
        const url = provider.authorizationUrl("state-123", "https://example.com/callback");

        expect(url).toContain("login.microsoftonline.com");
        expect(decodeURIComponent(url)).toContain("Calendars.ReadWrite");
        expect(decodeURIComponent(url)).toContain("OnlineMeetings.ReadWrite");
        expect(decodeURIComponent(url)).not.toContain("Mail.Read");
    });

    it("builds Zoom authorization URLs without client secrets", () => {
        const provider = new ZoomProvider("zoom-id", "zoom-secret");
        const url = provider.authorizationUrl("state-123", "https://example.com/callback");

        expect(url).toContain("zoom.us/oauth/authorize");
        expect(url).toContain("client_id=zoom-id");
        expect(url).not.toContain("zoom-secret");
    });

    it("builds Slack authorization URLs with posting scopes only", () => {
        const provider = new SlackProvider("slack-id", "slack-secret");
        const url = provider.authorizationUrl("state-123", "https://example.com/callback");

        expect(url).toContain("slack.com/oauth/v2/authorize");
        expect(decodeURIComponent(url)).toContain("chat:write");
        expect(decodeURIComponent(url)).toContain("incoming-webhook");
        expect(decodeURIComponent(url)).not.toContain("channels:history");
    });

    it("verifies Slack request signatures", () => {
        const timestamp = String(Math.floor(Date.now() / 1000));
        const rawBody = "token=abc&team_id=T123";
        const base = `v0:${timestamp}:${rawBody}`;
        const signature = `v0=${crypto.createHmac("sha256", "signing-secret").update(base).digest("hex")}`;

        expect(verifySlackSignature({
            signingSecret: "signing-secret",
            timestamp,
            rawBody,
            signature,
        })).toBe(true);
    });
});
