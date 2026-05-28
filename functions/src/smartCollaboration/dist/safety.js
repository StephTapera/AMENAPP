"use strict";
// safety.ts
// AMEN Smart Collaboration Layer — Safety Helpers
//
// Mirrors Swift SmartContextSafety in AmenSmartCollaborationContracts.swift.
// Pure functions — no side effects, no Firebase imports, no stored state.
//
// Non-negotiable rules enforced here:
//   1. AI-suggested text is always framed as "possible: …"
//   2. AI output is always citeable via a sourceMessageId
//   3. No body text, summary text, or prayer text ever reaches a log
//   4. Prayer signals require explicit opt-in before persistence or amplification
Object.defineProperty(exports, "__esModule", { value: true });
exports.REQUIRES_EXPLICIT_OPT_IN = void 0;
exports.labelAsSuggested = labelAsSuggested;
exports.labelWithSource = labelWithSource;
exports.sanitizeForLogging = sanitizeForLogging;
exports.requiresExplicitOptIn = requiresExplicitOptIn;
// MARK: - AI Output Labeling
/**
 * Frames AI-suggested text with a "possible: …" prefix so users always
 * know the content is a suggestion, not a statement of fact.
 */
function labelAsSuggested(text) {
    const trimmed = text.trim();
    if (!trimmed)
        return "";
    return `possible: ${trimmed}`;
}
/**
 * Frames AI output with a source citation so the origin message is always
 * traceable. Required on all AI-generated content surfaced to users.
 */
function labelWithSource(text, messageId) {
    const trimmed = text.trim();
    if (!trimmed)
        return "";
    return `${trimmed} [source: ${messageId}]`;
}
// MARK: - Logging Sanitizer
/**
 * Strips keys that are likely to contain free-form message body text before
 * any logging or analytics write. Only scalar analytics-safe values survive.
 *
 * CRITICAL: Never log raw message text, summary drafts, prayer themes, or
 * suggested action text. This function enforces that contract at call sites.
 */
function sanitizeForLogging(obj) {
    const sensitiveKeyPrefixes = [
        "summarytext",
        "suggestedtext",
        "bulletpoints",
        "keythemes",
        "prayertheme",
        "body",
        "text",
        "description",
        "content",
        "draft",
        "message",
        "transcript",
        "prayer",
    ];
    const sanitized = {};
    for (const [key, value] of Object.entries(obj)) {
        const lowerKey = key.toLowerCase();
        const isSensitive = sensitiveKeyPrefixes.some((prefix) => lowerKey.startsWith(prefix));
        if (isSensitive) {
            // Replace sensitive field with a safe marker — never drop the key
            // entirely so log schemas remain consistent.
            sanitized[key] = "[redacted]";
            continue;
        }
        // Allow only primitive analytics-safe types.
        switch (typeof value) {
            case "string":
            case "number":
            case "boolean":
                sanitized[key] = value;
                break;
            default:
                sanitized[key] = "[non-primitive]";
        }
    }
    return sanitized;
}
// MARK: - Opt-In Gate
/**
 * Categories that MUST NOT be auto-amplified, persisted, or broadcast without
 * an explicit opt-in action from the user.
 *
 * Any caller that wants to persist or push a signal in one of these categories
 * must first verify that requiresExplicitOptIn returns false for the category,
 * OR has proof of explicit user consent stored server-side.
 */
exports.REQUIRES_EXPLICIT_OPT_IN = ["prayerSignal"];
/**
 * Returns true if the given category requires explicit user opt-in before
 * any persistence, push notification, or group amplification.
 */
function requiresExplicitOptIn(category) {
    return exports.REQUIRES_EXPLICIT_OPT_IN.includes(category);
}
