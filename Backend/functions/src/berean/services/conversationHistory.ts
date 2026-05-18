/**
 * conversationHistory.ts
 *
 * Server-side sanitization of the client-supplied conversation history
 * forwarded to the Anthropic Berean proxy.
 *
 * Phase 8 of the AI/Berean release remediation: closes prompt-injection
 * via role override and unbounded-history smuggling.
 *
 * This module has no Firebase Functions runtime side effects so it is
 * safe to import directly from unit tests (unlike `bereanChatProxy.ts`,
 * which calls `defineSecret(...)` at module load).
 */

export const HISTORY_MAX_ENTRIES = 12;
export const HISTORY_MAX_CONTENT_CHARS = 1200;

export type SanitizedHistoryEntry = {
    role: "user" | "assistant";
    content: string;
};

/**
 * Sanitize the client-supplied conversation history before it is
 * forwarded to the provider.
 *
 * Guarantees:
 *   - Output items always have role in {"user","assistant"} and content:string.
 *   - Entries with any other role ("system"/"developer"/"tool"/missing/etc.)
 *     are dropped — they cannot smuggle a second system prompt past the
 *     server-built one.
 *   - Entries whose content is missing/non-stringifiable are dropped.
 *   - Content is coerced to string, NUL bytes stripped, and capped at
 *     HISTORY_MAX_CONTENT_CHARS characters.
 *   - Entries that become empty after sanitization are dropped.
 *   - The resulting array is capped at the last HISTORY_MAX_ENTRIES entries
 *     (oldest dropped first).
 *   - Unknown fields on each entry are not propagated.
 *   - A non-array input (null/undefined/object/string) returns [].
 */
export function sanitizeConversationHistory(
    raw: unknown
): SanitizedHistoryEntry[] {
    if (!Array.isArray(raw)) return [];
    const cleaned: SanitizedHistoryEntry[] = [];
    for (const item of raw) {
        if (!item || typeof item !== "object") continue;
        const entry = item as { role?: unknown; content?: unknown };
        const role = entry.role;
        if (role !== "user" && role !== "assistant") continue;
        if (entry.content == null) continue;
        let content: string;
        try {
            content = String(entry.content);
        } catch {
            continue;
        }
        // Strip NUL bytes — Anthropic rejects them and they're a known
        // smuggling vector for control characters.
        content = content
            .replace(/\u0000/g, "")
            .slice(0, HISTORY_MAX_CONTENT_CHARS);
        // Drop entries that are pure whitespace / empty after sanitization.
        if (content.trim().length === 0) continue;
        cleaned.push({ role, content });
    }
    return cleaned.slice(-HISTORY_MAX_ENTRIES);
}
