import * as crypto from "crypto";

type OAuthTokenResponse = {
    accessToken: string;
    refreshToken?: string;
    expiresAt?: number;
    scopes: string[];
    workspaceId?: string;
    workspaceName?: string;
    providerUserId?: string;
};

type ProviderMeetingResult = {
    providerEventId: string;
    joinUrl?: string;
    startsAt?: string;
    endsAt?: string;
};

interface IntegrationProviderAdapter {
    readonly provider: string;
    authorizationUrl(state: string, redirectUri: string): string;
    exchangeOAuthCode(code: string, redirectUri: string): Promise<OAuthTokenResponse>;
    refreshAccessToken(refreshToken: string): Promise<OAuthTokenResponse>;
    revokeToken(accessToken: string): Promise<void>;
}

const SLACK_AUTH_URL = "https://slack.com/oauth/v2/authorize";
const SLACK_TOKEN_URL = "https://slack.com/api/oauth.v2.access";
const SLACK_REVOKE_URL = "https://slack.com/api/auth.revoke";
const SLACK_SCOPES = ["chat:write", "incoming-webhook"];

export class SlackProvider implements IntegrationProviderAdapter {
    readonly provider = "slack" as const;

    constructor(private readonly clientId: string, private readonly clientSecret: string) {}

    authorizationUrl(state: string, redirectUri: string): string {
        const params = new URLSearchParams({
            client_id: this.clientId,
            scope: SLACK_SCOPES.join(","),
            redirect_uri: redirectUri,
            state,
        });
        return `${SLACK_AUTH_URL}?${params.toString()}`;
    }

    async exchangeOAuthCode(code: string, redirectUri: string): Promise<OAuthTokenResponse> {
        const response = await fetch(SLACK_TOKEN_URL, {
            method: "POST",
            headers: {"Content-Type": "application/x-www-form-urlencoded"},
            body: new URLSearchParams({
                client_id: this.clientId,
                client_secret: this.clientSecret,
                code,
                redirect_uri: redirectUri,
            }).toString(),
        });
        if (!response.ok) throw new Error(`slack_oauth_${response.status}`);
        const json = await response.json() as {
            ok: boolean;
            error?: string;
            access_token?: string;
            scope?: string;
            team?: {id?: string; name?: string};
            authed_user?: {id?: string};
        };
        if (!json.ok || !json.access_token) {
            throw new Error(`slack_oauth_${json.error ?? "unknown"}`);
        }
        return {
            accessToken: json.access_token,
            scopes: json.scope?.split(",").filter(Boolean) ?? SLACK_SCOPES,
            workspaceId: json.team?.id,
            workspaceName: json.team?.name,
            providerUserId: json.authed_user?.id,
        };
    }

    async refreshAccessToken(): Promise<OAuthTokenResponse> {
        throw new Error("slack_refresh_not_supported_for_bot_token");
    }

    async revokeToken(accessToken: string): Promise<void> {
        await fetch(SLACK_REVOKE_URL, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${accessToken}`,
                "Content-Type": "application/x-www-form-urlencoded",
            },
            body: new URLSearchParams({test: "false"}).toString(),
        });
    }

    async createMeeting(): Promise<ProviderMeetingResult> {
        throw new Error("slack_does_not_create_meetings");
    }
}

export function verifySlackSignature(input: {
    signingSecret: string;
    timestamp: string;
    rawBody: string;
    signature: string;
}): boolean {
    const ts = Number(input.timestamp);
    if (!Number.isFinite(ts)) return false;
    if (Math.abs(Math.floor(Date.now() / 1000) - ts) > 60 * 5) return false;

    const base = `v0:${input.timestamp}:${input.rawBody}`;
    const expected = `v0=${crypto.createHmac("sha256", input.signingSecret).update(base).digest("hex")}`;
    return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(input.signature));
}
