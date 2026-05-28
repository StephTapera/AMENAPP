import type {CreateMeetingInput, IntegrationProviderAdapter, OAuthTokenResponse, ProviderMeetingResult} from "../models";

const ZOOM_AUTH_URL = "https://zoom.us/oauth/authorize";
const ZOOM_TOKEN_URL = "https://zoom.us/oauth/token";
const ZOOM_API_URL = "https://api.zoom.us/v2";
const ZOOM_SCOPES = ["meeting:write", "meeting:read", "user:read"];

export class ZoomProvider implements IntegrationProviderAdapter {
    readonly provider = "zoom" as const;

    constructor(private readonly clientId: string, private readonly clientSecret: string) {}

    authorizationUrl(state: string, redirectUri: string): string {
        const params = new URLSearchParams({
            response_type: "code",
            client_id: this.clientId,
            redirect_uri: redirectUri,
            state,
        });
        return `${ZOOM_AUTH_URL}?${params.toString()}`;
    }

    async exchangeOAuthCode(code: string, redirectUri: string): Promise<OAuthTokenResponse> {
        return this.exchangeToken(new URLSearchParams({
            grant_type: "authorization_code",
            code,
            redirect_uri: redirectUri,
        }));
    }

    async refreshAccessToken(refreshToken: string): Promise<OAuthTokenResponse> {
        return this.exchangeToken(new URLSearchParams({
            grant_type: "refresh_token",
            refresh_token: refreshToken,
        }));
    }

    async revokeToken(accessToken: string): Promise<void> {
        await fetch("https://zoom.us/oauth/revoke", {
            method: "POST",
            headers: {
                "Authorization": this.basicAuthHeader(),
                "Content-Type": "application/x-www-form-urlencoded",
            },
            body: new URLSearchParams({token: accessToken}).toString(),
        });
    }

    async createMeeting(accessToken: string, input: CreateMeetingInput): Promise<ProviderMeetingResult> {
        const response = await fetch(`${ZOOM_API_URL}/users/me/meetings`, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${accessToken}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                topic: input.title,
                type: 2,
                start_time: input.startTime.toISOString(),
                duration: Math.max(15, Math.ceil((input.endTime.getTime() - input.startTime.getTime()) / 60000)),
                agenda: [input.scriptureFocus, input.agenda, input.description].filter(Boolean).join("\n\n").slice(0, 1800),
                settings: {
                    waiting_room: true,
                    meeting_authentication: false,
                    join_before_host: false,
                    mute_upon_entry: true,
                    approval_type: 0,
                    audio: "both",
                },
            }),
        });
        if (!response.ok) {
            throw new Error(`zoom_create_meeting_${response.status}`);
        }
        const json = await response.json() as {id?: number | string; join_url?: string};
        if (!json.id || !json.join_url) {
            throw new Error("zoom_create_meeting_missing_join_url");
        }
        return {
            providerMeetingId: String(json.id),
            meetingUrl: json.join_url,
            rawStatus: "created",
        };
    }

    private async exchangeToken(params: URLSearchParams): Promise<OAuthTokenResponse> {
        const response = await fetch(ZOOM_TOKEN_URL, {
            method: "POST",
            headers: {
                "Authorization": this.basicAuthHeader(),
                "Content-Type": "application/x-www-form-urlencoded",
            },
            body: params.toString(),
        });
        if (!response.ok) {
            throw new Error(`zoom_oauth_${response.status}`);
        }
        const json = await response.json() as {
            access_token: string;
            refresh_token?: string;
            expires_in?: number;
            scope?: string;
        };
        return {
            accessToken: json.access_token,
            refreshToken: json.refresh_token,
            expiresIn: json.expires_in,
            scopes: json.scope?.split(" ").filter(Boolean) ?? ZOOM_SCOPES,
        };
    }

    private basicAuthHeader(): string {
        return `Basic ${Buffer.from(`${this.clientId}:${this.clientSecret}`).toString("base64")}`;
    }
}
