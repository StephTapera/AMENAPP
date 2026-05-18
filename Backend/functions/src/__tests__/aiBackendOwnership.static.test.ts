/**
 * aiBackendOwnership.static.test.ts
 *
 * Phase P1-1 / P1-8 — static-source CI regression test that locks the
 * canonical AI backend ownership map (Docs/AI_BACKEND_OWNERSHIP.md) in
 * place.
 *
 * Fails the build if:
 *   1. A canonical owner file (modern codebase) is missing or renamed,
 *      so iOS callers would silently fall back to a legacy duplicate.
 *   2. A legacy file in `functions/` that we marked as deprecated
 *      removed its `@deprecated` marker.
 *
 * Pure source-reading test, no Firebase runtime.
 */

import * as fs from "fs";
import * as path from "path";

const REPO_ROOT = path.resolve(__dirname, "../../../..");

/**
 * Canonical owners. Every entry MUST exist on disk; if iOS callers
 * for the matching feature start hitting a legacy duplicate because
 * the canonical owner was renamed or deleted, this test catches it.
 */
const CANONICAL_OWNERS: ReadonlyArray<{ feature: string; file: string }> = [
    { feature: "Berean chat (non-stream)", file: "Backend/functions/src/bereanChatProxy.ts" },
    { feature: "Berean chat (SSE stream)", file: "Backend/functions/src/bereanChatProxyStream.ts" },
    { feature: "Berean Pulse",            file: "Backend/functions/src/bereanPulse.ts" },
    { feature: "Berean structured response", file: "Backend/functions/src/berean/controllers/generateStructuredResponse.ts" },
    { feature: "Daily verse",             file: "Backend/functions/src/generateDailyVerse.ts" },
    { feature: "Whisper proxy",           file: "Backend/functions/src/whisperProxy.ts" },
    { feature: "OpenAI proxy",            file: "Backend/functions/src/openAIProxy.ts" },
    { feature: "Voice prayer comments",   file: "Backend/functions/src/voicePrayerComments.ts" },
    { feature: "Selah media",             file: "Backend/functions/src/selahMedia.ts" },
    { feature: "Trust intelligence",      file: "Backend/functions/src/trustIntelligence.ts" },
    { feature: "Media moderation",        file: "Backend/functions/src/mediaModerationPipeline.ts" },
    { feature: "Think-First validator",   file: "Backend/functions/src/thinkFirst/validateThinkFirstCheck.ts" },
];

/**
 * Legacy files that MUST carry an `@deprecated` JSDoc tag. If the tag
 * disappears the static gate alerts the reviewer — preventing silent
 * "untangling" of the deprecation contract.
 */
const DEPRECATED_LEGACY: ReadonlyArray<string> = [
    "functions/openAIFunctions.js",
    "functions/bereanFunctions.js",
    "functions/aiPromptFeatures.js",
    "functions/bereanFeaturesFunctions.js",
    "functions/heyfeedFunctions.js",
];

/**
 * The canonical ownership doc must exist and must reference the
 * deprecation contract.
 */
const OWNERSHIP_DOC = "Docs/AI_BACKEND_OWNERSHIP.md";

function abs(rel: string): string {
    return path.join(REPO_ROOT, rel);
}

describe("AI backend ownership (static)", () => {
    test("canonical ownership doc exists", () => {
        expect(fs.existsSync(abs(OWNERSHIP_DOC))).toBe(true);
    });

    test("ownership doc mentions the deprecation contract", () => {
        const src = fs.readFileSync(abs(OWNERSHIP_DOC), "utf8");
        expect(src).toMatch(/@deprecated/);
        expect(src).toMatch(/canonical/i);
    });

    test.each(CANONICAL_OWNERS)(
        "canonical owner exists: $feature ($file)",
        ({ file }) => {
            const p = abs(file);
            const exists = fs.existsSync(p);
            if (!exists) {
                throw new Error(
                    `Canonical AI owner file missing: ${file}. ` +
                        `If you renamed it, update Docs/AI_BACKEND_OWNERSHIP.md ` +
                        `and CANONICAL_OWNERS in this test.`
                );
            }
            expect(exists).toBe(true);
        }
    );

    test.each(DEPRECATED_LEGACY)(
        "legacy file carries @deprecated JSDoc: %s",
        (relPath) => {
            const p = abs(relPath);
            if (!fs.existsSync(p)) {
                // Legacy file deleted — that's a successful retirement,
                // not a failure. Don't require the marker.
                return;
            }
            const head = fs.readFileSync(p, "utf8").slice(0, 2000);
            expect(head).toMatch(/@deprecated/);
        }
    );
});
