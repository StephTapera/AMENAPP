/**
 * aiDisclosure.ts
 *
 * Pure-function helper that ensures every user-visible Berean assistant
 * response begins with the AI-generated disclosure line.
 *
 * Phase P1-3 + P1-4 / Phase F: extracted from bereanChatProxy.ts so the
 * streaming proxy (bereanChatProxyStream.ts) can apply the same
 * disclosure at the terminal SSE event. Previously only the non-
 * streaming path prepended the disclosure; streaming responses went
 * out without it.
 *
 * No Firebase Functions runtime side effects — safe to import from
 * unit tests.
 */

/**
 * The exact disclosure line prepended to every Berean AI response.
 * Exposed for unit tests; production callers should use
 * `ensureAIDisclosure(...)` rather than concatenating manually.
 */
export const AI_DISCLOSURE_LINE =
    "AI-generated response — not pastoral, medical, legal, or clinical advice.";

/**
 * Prepend the AI disclosure if it is not already present at the start
 * of the text. Idempotent — calling this twice on the same string
 * returns the same value as calling it once.
 *
 * Matching is case-insensitive on the disclosure prefix so a server
 * patch that adjusts capitalization later does not double-prepend.
 */
export function ensureAIDisclosure(text: string): string {
    if (typeof text !== "string") {
        return `${AI_DISCLOSURE_LINE}\n\n`;
    }
    const head = text.slice(0, AI_DISCLOSURE_LINE.length).toLowerCase();
    if (head.startsWith(AI_DISCLOSURE_LINE.slice(0, 24).toLowerCase())) {
        return text;
    }
    return `${AI_DISCLOSURE_LINE}\n\n${text}`;
}
