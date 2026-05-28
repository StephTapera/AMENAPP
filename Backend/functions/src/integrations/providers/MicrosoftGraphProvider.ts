import type {CreateMeetingInput, IntegrationProviderAdapter, OAuthTokenResponse, ProviderMeetingResult} from "../models";

const GRAPH_AUTH_URL = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize";
const GRAPH_TOKEN_URL = "https://login.microsoftonline.com/common/oauth2/v2.0/token";
const GRAPH_API_URL = "https://graph.microsoft.com/v1.0";
const MICROSOFT_SCOPES = [
    "offline_access",
    "User.Read",
    "Calendars.ReadWrite",
    "OnlineMeetings.ReadWrite",
];

export class MicrosoftGraphProvider implements IntegrationProviderAdapter {
    readonly provider = "microsoft" as const;

    constructor(private readonly clientId: string, private readonly clientSecret: string) {}

    authorizationUrl(state: string, redirectUri: string): string {
        const params = new URLSearchParams({
            client_id: this.clientId,
            response_type: "code",
            redirect_uri: redirectUri,
            response_mode: "query",
            scope: MICROSOFT_SCOPES.join(" "),
            state,
            prompt: "select_account",
        });
        return `${GRAPH_AUTH_URL}?${params.toString()}`;
    }

    async exchangeOAuthCode(code: string, redirectUri: string): Promise<OAuthTokenResponse> {
        return this.exchangeToken({
            client_id: this.clientId,
            client_secret: this.clientSecret,
            code,
            redirect_uri: redirectUri,
            grant_type: "authorization_code",
            scope: MICROSOFT_SCOPES.join(" "),
        });
    }

    async refreshAccessToken(refreshToken: string): Promise<OAuthTokenResponse> {
        return this.exchangeToken({
            client_id: this.clientId,
            client_secret: this.clientSecret,
            refresh_token: refreshToken,
            grant_type: "refresh_token",
            scope: MICROSOFT_SCOPES.join(" "),
        });
    }

    async revokeToken(): Promise<void> {
        // Microsoft personal/work OAuth tokens are revoked through user/admin consent
        // management. AMEN marks the account revoked server-side and stops use.
    }

    async createMeeting(accessToken: string, input: CreateMeetingInput): Promise<ProviderMeetingResult> {
        const response = await fetch(`${GRAPH_API_URL}/me/events`, {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${accessToken}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                subject: input.title,
                body: {
                    contentType: "text",
                    content: [input.scriptureFocus, input.agenda, input.description].filter(Boolean).join("\n\n"),
                },
                start: {dateTime: input.startTime.toISOString(), timeZone: "UTC"},
                end: {dateTime: input.endTime.toISOString(), timeZone: "UTC"},
                attendees: input.participants
                    .filter((participant) => participant.email)
                    .map((participant) => ({
                        emailAddress: {
                            address: participant.email,
                            name: participant.displayName ?? participant.email,
                        },
                        type: "required",
                    })),
                isOnlineMeeting: true,
                onlineMeetingProvider: "teamsForBusiness",
            }),
        });

        if (!response.ok) {
            throw new Error(`microsoft_create_meeting_${response.status}`);
        }
        const json = await response.json() as {id?: string; onlineMeeting?: {joinUrl?: string}};
        if (!json.id || !json.onlineMeeting?.joinUrl) {
            throw new Error("microsoft_create_meeting_missing_join_url");
        }
        return {
            providerMeetingId: json.id,
            meetingUrl: json.onlineMeeting.joinUrl,
            rawStatus: "created",
        };
    }

    private async exchangeToken(params: Record<string, string>): Promise<OAuthTokenResponse> {
        const response = await fetch(GRAPH_TOKEN_URL, {
            method: "POST",
            headers: {"Content-Type": "application/x-www-form-urlencoded"},
            body: new URLSearchParams(params).toString(),
        });
        if (!response.ok) {
            throw new Error(`microsoft_oauth_${response.status}`);
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
            scopes: json.scope?.split(" ").filter(Boolean) ?? MICROSOFT_SCOPES,
        };
    }
}
