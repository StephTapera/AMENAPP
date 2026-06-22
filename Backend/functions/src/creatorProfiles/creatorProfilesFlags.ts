// creatorProfilesFlags.ts
// AMEN — Creator Profiles: server-authoritative feature-flag gate.
//
// Mirrors the serverFeatureFlags.ts pattern, but INVERTED defaults: every Creator-Hub
// flag defaults OFF. A missing/unreadable flag doc means the feature is DISABLED, never
// accidentally enabled. Flags live in Firestore `system/creatorProfileFlags` (admin-SDK
// only; clients cannot read it — covered by the `system/{doc}` deny-all rule).
//
// Human flip step (see WAVE0_FREEZE.md): to enable a feature, set both
//   - Remote Config key (client gate, e.g. `creator_profiles_enabled`)
//   - system/creatorProfileFlags.<camelKey> = true (server gate)

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { HttpsError } from "firebase-functions/v2/https";
import { CreatorHubFlagKey, CREATOR_HUB_FLAGS } from "./creatorProfileTypes";

export interface CreatorHubServerFlags {
    creatorProfilesEnabled: boolean;
    creatorEventsEnabled: boolean;
    creatorTeachingSearchEnabled: boolean;
    creatorResourcesEnabled: boolean;
    creatorPrayerBoardEnabled: boolean;
    creatorCommunityEnabled: boolean;
    creatorAiAssistantEnabled: boolean;
    creatorLiveModeEnabled: boolean;
    creatorSupportDonationsEnabled: boolean;
    creatorVoiceConsumptionEnabled: boolean;
}

/** Safe defaults: EVERYTHING OFF. */
const OFF_DEFAULTS: CreatorHubServerFlags = {
    creatorProfilesEnabled: false,
    creatorEventsEnabled: false,
    creatorTeachingSearchEnabled: false,
    creatorResourcesEnabled: false,
    creatorPrayerBoardEnabled: false,
    creatorCommunityEnabled: false,
    creatorAiAssistantEnabled: false,
    creatorLiveModeEnabled: false,
    creatorSupportDonationsEnabled: false,
    creatorVoiceConsumptionEnabled: false,
};

/** Maps a Remote Config flag key → the camelCase server-flag field. */
const KEY_TO_FIELD: Record<CreatorHubFlagKey, keyof CreatorHubServerFlags> = {
    [CREATOR_HUB_FLAGS.profilesEnabled]: "creatorProfilesEnabled",
    [CREATOR_HUB_FLAGS.eventsEnabled]: "creatorEventsEnabled",
    [CREATOR_HUB_FLAGS.teachingSearchEnabled]: "creatorTeachingSearchEnabled",
    [CREATOR_HUB_FLAGS.resourcesEnabled]: "creatorResourcesEnabled",
    [CREATOR_HUB_FLAGS.prayerBoardEnabled]: "creatorPrayerBoardEnabled",
    [CREATOR_HUB_FLAGS.communityEnabled]: "creatorCommunityEnabled",
    [CREATOR_HUB_FLAGS.aiAssistantEnabled]: "creatorAiAssistantEnabled",
    [CREATOR_HUB_FLAGS.liveModeEnabled]: "creatorLiveModeEnabled",
    [CREATOR_HUB_FLAGS.supportDonationsEnabled]: "creatorSupportDonationsEnabled",
    [CREATOR_HUB_FLAGS.voiceConsumptionEnabled]: "creatorVoiceConsumptionEnabled",
};

let cache: CreatorHubServerFlags | null = null;
let cacheExpiresAt = 0;
const CACHE_TTL_MS = 5 * 60 * 1000;

/** Reads the server flag doc. Any read failure / missing field → OFF. */
export async function getCreatorHubFlags(): Promise<CreatorHubServerFlags> {
    const now = Date.now();
    if (cache !== null && now < cacheExpiresAt) return cache;

    try {
        const snap = await admin.firestore().collection("system").doc("creatorProfileFlags").get();
        const data = snap.exists ? (snap.data() ?? {}) : {};
        const flags = { ...OFF_DEFAULTS };
        (Object.keys(OFF_DEFAULTS) as (keyof CreatorHubServerFlags)[]).forEach((field) => {
            flags[field] = typeof data[field] === "boolean" ? data[field] : false;
        });
        cache = flags;
        cacheExpiresAt = now + CACHE_TTL_MS;
        return flags;
    } catch (err) {
        functions.logger.error("[CreatorHubFlags] read failed — defaulting OFF.", err);
        return OFF_DEFAULTS; // do not cache on error
    }
}

export async function isCreatorHubFlagEnabled(key: CreatorHubFlagKey): Promise<boolean> {
    const flags = await getCreatorHubFlags();
    return flags[KEY_TO_FIELD[key]] === true;
}

/**
 * Gate guard for callables. Throws `failed-precondition` when the flag is OFF.
 * Every Creator-Hub function calls this first, so an un-flipped feature denies cleanly.
 */
export async function assertCreatorHubFlag(key: CreatorHubFlagKey): Promise<void> {
    if (!(await isCreatorHubFlagEnabled(key))) {
        throw new HttpsError("failed-precondition", `Feature is not enabled: ${key}`);
    }
}
