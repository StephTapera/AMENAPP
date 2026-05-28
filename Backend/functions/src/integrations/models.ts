export type AmenIntegrationProvider = "microsoft" | "zoom" | "slack";
export type AmenIntegrationStatus = "connected" | "expired" | "revoked" | "error";
export type AmenMeetingPrivacyLevel = "private" | "space" | "church" | "organization";

export interface EncryptedTokenEnvelope {
    algorithm: "aes-256-gcm";
    keyVersion: string;
    iv: string;
    ciphertext: string;
    authTag: string;
}

export interface AmenIntegrationAccount {
    userId: string;
    provider: AmenIntegrationProvider;
    encryptedAccessToken: EncryptedTokenEnvelope;
    encryptedRefreshToken?: EncryptedTokenEnvelope;
    scopes: string[];
    workspaceId?: string;
    workspaceName?: string;
    providerUserId?: string;
    connectedAt: FirebaseFirestore.FieldValue;
    expiresAt?: FirebaseFirestore.Timestamp;
    revokedAt?: FirebaseFirestore.FieldValue | null;
    status: AmenIntegrationStatus;
    updatedAt: FirebaseFirestore.FieldValue;
}

export interface AmenMeetingParticipant {
    userId?: string;
    email?: string;
    displayName?: string;
    role?: "host" | "attendee";
}

export interface AmenMeeting {
    provider: AmenIntegrationProvider;
    providerMeetingId: string;
    meetingUrl: string;
    title: string;
    description?: string;
    agenda?: string;
    scriptureFocus?: string;
    startTime: FirebaseFirestore.Timestamp;
    endTime: FirebaseFirestore.Timestamp;
    createdBy: string;
    amenSpaceId?: string;
    organizationId?: string;
    privacyLevel: AmenMeetingPrivacyLevel;
    participants: AmenMeetingParticipant[];
    followUpStatus: "not_started" | "scheduled" | "completed";
    createdAt: FirebaseFirestore.FieldValue;
    updatedAt: FirebaseFirestore.FieldValue;
}

export interface AmenMeetingRecap {
    summary: string;
    prayerRequests: string[];
    actionItems: string[];
    scripturesReferenced: string[];
    bereanInsights: string[];
    followUpSuggestions: string[];
    createdAt: FirebaseFirestore.FieldValue;
    createdBy: string;
}

export interface AmenIntegrationAuditLog {
    provider: AmenIntegrationProvider;
    action: string;
    actorId: string;
    timestamp: FirebaseFirestore.FieldValue;
    success: boolean;
    errorCode?: string;
    securityFlags: string[];
    metadata?: Record<string, unknown>;
}

export interface OAuthTokenResponse {
    accessToken: string;
    refreshToken?: string;
    expiresIn?: number;
    scopes: string[];
    workspaceId?: string;
    workspaceName?: string;
    providerUserId?: string;
}

export interface CreateMeetingInput {
    title: string;
    description?: string;
    agenda?: string;
    scriptureFocus?: string;
    startTime: Date;
    endTime: Date;
    participants: AmenMeetingParticipant[];
    amenSpaceId?: string;
    organizationId?: string;
    privacyLevel: AmenMeetingPrivacyLevel;
}

export interface ProviderMeetingResult {
    providerMeetingId: string;
    meetingUrl: string;
    rawStatus?: string;
}

export interface IntegrationProviderAdapter {
    provider: AmenIntegrationProvider;
    authorizationUrl(state: string, redirectUri: string): string;
    exchangeOAuthCode(code: string, redirectUri: string): Promise<OAuthTokenResponse>;
    refreshAccessToken(refreshToken: string): Promise<OAuthTokenResponse>;
    revokeToken(accessToken: string, refreshToken?: string): Promise<void>;
    createMeeting(accessToken: string, input: CreateMeetingInput): Promise<ProviderMeetingResult>;
}
