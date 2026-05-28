import * as admin from "firebase-admin";

export interface AmenIntegrationFlags {
    amenIntegrationsPlatformEnabled: boolean;
    microsoftGraphEnabled: boolean;
    zoomEnabled: boolean;
    slackEnabled: boolean;
    meetingCreationEnabled: boolean;
    organizationIntegrationsEnabled: boolean;
    bereanMeetingIntelligenceEnabled: boolean;
}

const SAFE_DEFAULTS: AmenIntegrationFlags = {
    amenIntegrationsPlatformEnabled: false,
    microsoftGraphEnabled: false,
    zoomEnabled: false,
    slackEnabled: false,
    meetingCreationEnabled: false,
    organizationIntegrationsEnabled: false,
    bereanMeetingIntelligenceEnabled: false,
};

let cache: AmenIntegrationFlags | null = null;
let cacheExpiresAt = 0;
const CACHE_TTL_MS = 5 * 60 * 1000;

export async function getAmenIntegrationFlags(): Promise<AmenIntegrationFlags> {
    const now = Date.now();
    if (cache && now < cacheExpiresAt) return cache;

    try {
        const snap = await admin.firestore().collection("system").doc("amenIntegrationFlags").get();
        const data = snap.data() ?? {};
        const flags: AmenIntegrationFlags = {
            amenIntegrationsPlatformEnabled: typeof data.amenIntegrationsPlatformEnabled === "boolean" ? data.amenIntegrationsPlatformEnabled : SAFE_DEFAULTS.amenIntegrationsPlatformEnabled,
            microsoftGraphEnabled: typeof data.microsoftGraphEnabled === "boolean" ? data.microsoftGraphEnabled : SAFE_DEFAULTS.microsoftGraphEnabled,
            zoomEnabled: typeof data.zoomEnabled === "boolean" ? data.zoomEnabled : SAFE_DEFAULTS.zoomEnabled,
            slackEnabled: typeof data.slackEnabled === "boolean" ? data.slackEnabled : SAFE_DEFAULTS.slackEnabled,
            meetingCreationEnabled: typeof data.meetingCreationEnabled === "boolean" ? data.meetingCreationEnabled : SAFE_DEFAULTS.meetingCreationEnabled,
            organizationIntegrationsEnabled: typeof data.organizationIntegrationsEnabled === "boolean" ? data.organizationIntegrationsEnabled : SAFE_DEFAULTS.organizationIntegrationsEnabled,
            bereanMeetingIntelligenceEnabled: typeof data.bereanMeetingIntelligenceEnabled === "boolean" ? data.bereanMeetingIntelligenceEnabled : SAFE_DEFAULTS.bereanMeetingIntelligenceEnabled,
        };
        cache = flags;
        cacheExpiresAt = now + CACHE_TTL_MS;
        return flags;
    } catch {
        return SAFE_DEFAULTS;
    }
}

export function providerEnabled(flags: AmenIntegrationFlags, provider: string): boolean {
    if (!flags.amenIntegrationsPlatformEnabled) return false;
    if (provider === "microsoft") return flags.microsoftGraphEnabled;
    if (provider === "zoom") return flags.zoomEnabled;
    if (provider === "slack") return flags.slackEnabled;
    return false;
}
