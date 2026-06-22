import * as admin from "firebase-admin";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { enforceRateLimit } from "./rateLimit";

const db = admin.firestore();

const SETTINGS_RATE_LIMIT = [
    { name: "settings_update_1min", windowMs: 60_000, maxCalls: 30 },
    { name: "settings_update_1day", windowMs: 86_400_000, maxCalls: 1000 },
];

const ALLOWED_KEYS = new Set([
    "amenSettingsSuggestedDismissed",
    "amen_account_type",
    "amen_private_account", "amen_activity_status", "amen_read_receipts", "amen_show_likes", "amen_find_by_email", "amen_find_by_phone", "amen_comment_permission", "amen_mention_permission", "amen_profile_discoverability",
    "amen_hidden_words", "amen_strict_filter", "amen_sensitive_blur", "amen_anti_harassment",
    "amen_dm_permission", "amen_msg_requests", "amen_online_in_dms", "amen_dm_read_receipts", "amen_typing_indicator", "amen_media_preview", "amen_link_preview", "amen_dm_curfew_enabled", "amen_dm_curfew_start_hour", "amen_dm_curfew_end_hour",
    "amen_notif_likes", "amen_notif_comments", "amen_notif_replies", "amen_notif_followers", "amen_notif_follow_requests", "amen_notif_mentions", "amen_notif_tags", "amen_notif_reposts", "amen_notif_prayer", "amen_notif_events", "amen_notif_community", "amen_notif_berean", "amen_notif_scheduled", "amen_notif_drafts", "amen_notif_safety", "amen_notif_updates", "amen_notif_security", "amen_notif_digest", "amen_notif_quiet_enabled", "amen_notif_quiet_start_hour", "amen_notif_quiet_end_hour",
    "amen_default_audience", "amen_draft_autosave", "amen_draft_berean_resume", "amen_post_scheduling", "amen_sensitive_warning", "amen_ai_disclosure", "amen_true_source", "amen_auto_content_warnings", "amen_post_template_signature", "amen_post_template_call_to_action", "amen_post_template_include_scripture",
    "amen_feed_mode", "amen_sensitive_content", "amen_autoplay", "amen_show_like_counts", "amen_show_follower_counts", "amen_hide_from_suggestions", "amen_interest_worship", "amen_interest_scripture", "amen_interest_service", "amen_interest_family", "amen_interest_wellness", "amen_interest_local_church",
    "amen_berean_enabled", "amen_berean_mode", "amen_berean_memory", "amen_berean_transparency", "amen_berean_data_usage", "amen_berean_in_feed", "amen_berean_style",
    "amen_notes_default_folder", "amen_notes_auto_scripture", "amen_notes_growth_loop", "amen_notes_sync", "amen_notes_export_format", "amen_notes_sermon_capture", "amen_notes_theme", "amen_notes_use_theme_for_exports",
    "amen_reduce_motion", "amen_high_contrast", "amen_bold_text", "amen_alt_text", "amen_screen_reader", "amen_app_text_scale", "amen_caption_size", "amen_caption_background", "amen_caption_speaker_names",
    "amen_download_quality", "amen_preload_videos", "amen_ai_processing", "amen_data_collection_personalization", "amen_data_collection_diagnostics", "amen_data_collection_location", "amen_data_retention_posts", "amen_data_retention_search", "amen_data_retention_ai",
    "amen_2fa_enabled", "amen_login_alerts",
    "amen_teen_mode", "amen_time_limit", "amen_family_quiet", "amen_content_restrict", "amen_private_by_default", "amen_guardian_review_required", "amen_guardian_digest", "amen_guardian_invite_email",
    "amen_creator_weekly_digest", "amen_creator_prayerful_metrics", "amen_creator_growth_prompts",
]);

function requireAuth(request: CallableRequest): string {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return uid;
}

function cleanValues(raw: unknown): Record<string, string> {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
        throw new HttpsError("invalid-argument", "values must be an object.");
    }
    const values: Record<string, string> = {};
    for (const [key, value] of Object.entries(raw)) {
        if (!ALLOWED_KEYS.has(key)) {
            continue;
        }
        if (typeof value !== "string") {
            throw new HttpsError("invalid-argument", `${key} must be a string.`);
        }
        const trimmed = value.trim();
        if (trimmed.length > 240) {
            throw new HttpsError("invalid-argument", `${key} is too long.`);
        }
        values[key] = trimmed;
    }
    return values;
}

export const updateUserSettings = onCall(
    { region: "us-central1", enforceAppCheck: true, timeoutSeconds: 20 },
    async (request: CallableRequest) => {
        const uid = requireAuth(request);
        await enforceRateLimit(uid, SETTINGS_RATE_LIMIT);
        const values = cleanValues(request.data?.values);
        await db.collection("userSettings").doc(uid).set({
            uid,
            values,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return { ok: true, savedKeys: Object.keys(values).length };
    }
);
