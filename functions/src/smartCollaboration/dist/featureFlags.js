"use strict";
// featureFlags.ts
// AMEN Smart Collaboration Layer — Remote Config Flag Keys
//
// Cloud Functions gate themselves on these Remote Config flags before doing any work.
// All flags default to false — feature is OFF unless explicitly enabled in Firebase Console.
//
// Keys mirror the client-side RemoteKillSwitch.swift declarations.
Object.defineProperty(exports, "__esModule", { value: true });
exports.SmartCollabFlags = void 0;
exports.isSmartFlagEnabled = isSmartFlagEnabled;
const remote_config_1 = require("firebase-admin/remote-config");
// MARK: - Flag Key Registry
/** Remote Config parameter keys for all Smart Collaboration features. */
exports.SmartCollabFlags = {
    SMART_CONTEXT: "kill_smart_context_enabled",
    GROUP_PULSE: "kill_group_pulse_enabled",
    PRAYER_DETECTION: "kill_prayer_detection_enabled",
    ACTION_EXTRACTION: "kill_action_extraction_enabled",
    SMART_REPLIES: "kill_smart_replies_enabled",
    MEDIA_INTELLIGENCE: "kill_media_intelligence_enabled",
    SMART_PRESENCE: "kill_smart_presence_enabled",
};
// MARK: - Flag Evaluation
/**
 * Returns the boolean value of a Smart Collaboration Remote Config flag.
 *
 * Defaults to `false` on any error — functions MUST NOT proceed when this
 * returns false. The safe default ensures new capabilities cannot activate
 * without an explicit Console configuration change.
 */
async function isSmartFlagEnabled(flagKey) {
    try {
        const rc = (0, remote_config_1.getRemoteConfig)();
        const template = await rc.getTemplate();
        const param = template.parameters[flagKey];
        if (!param) {
            // Key not yet published to Remote Config — treat as disabled.
            return false;
        }
        // Prefer the explicit default value; fall back to conditional groups.
        const defaultValue = param.defaultValue;
        if (!defaultValue || !("value" in defaultValue)) {
            return false;
        }
        const raw = defaultValue.value;
        return raw === "true";
    }
    catch (err) {
        // Remote Config fetch failed — safe default: disabled.
        console.warn(`[SmartCollab] Remote Config fetch failed for flag "${flagKey}". Defaulting to false.`, err);
        return false;
    }
}
