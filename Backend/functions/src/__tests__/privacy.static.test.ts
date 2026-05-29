/**
 * privacy.static.test.ts
 *
 * Static invariant tests for the privacy module (Agent 5).
 *
 * These tests parse source files as strings and assert structural invariants
 * that must remain true to guarantee GDPR/CCPA compliance. No Firebase
 * runtime required — pure string-matching guards.
 *
 * Each test encodes a COMPLIANCE REQUIREMENT:
 *   - If a test fails after a code change, the change has broken a privacy
 *     guarantee and must be reverted or the guarantee must be restored.
 */

import * as fs from "fs";
import * as path from "path";

// ── Helpers ────────────────────────────────────────────────────────────────────

function readSrc(relPath: string): string {
    return fs.readFileSync(path.join(__dirname, "..", relPath), "utf-8");
}

// ── deleteBereanHistory.ts invariants ─────────────────────────────────────────

describe("deleteBereanHistory: coverage invariants", () => {
    const src = readSrc("privacy/deleteBereanHistory.ts");

    test("deletes berean_conversations top-level collection", () => {
        expect(src).toMatch(/berean_conversations/);
    });

    test("deletes berean_messages via conversationId lookup", () => {
        expect(src).toMatch(/berean_messages/);
        expect(src).toMatch(/conversationId.*in/);
    });

    test("deletes bereanMemory subcollection", () => {
        expect(src).toMatch(/bereanMemory/);
    });

    test("deletes bereanInsights subcollection", () => {
        expect(src).toMatch(/bereanInsights/);
    });

    test("writes a compliance audit log entry", () => {
        expect(src).toMatch(/bereanAuditEvents/);
        expect(src).toMatch(/delete_all_berean_history/);
    });

    test("enforces App Check", () => {
        expect(src).toMatch(/enforceAppCheck:\s*true/);
    });

    test("requires authentication", () => {
        expect(src).toMatch(/request\.auth\?\.uid/);
        expect(src).toMatch(/unauthenticated/);
    });

    test("handles berean_messages via conversation ID chunks (Firestore in-query limit)", () => {
        // Must slice convoy IDs into chunks of ≤30 for Firestore `in` operator.
        expect(src).toMatch(/slice.*30|i\s*\+=\s*30/);
    });
});

// ── userDataExport.ts invariants ──────────────────────────────────────────────

describe("userDataExport: coverage invariants", () => {
    const src = readSrc("privacy/userDataExport.ts");

    test("collects berean_conversations", () => {
        expect(src).toMatch(/berean_conversations/);
    });

    test("collects berean_messages", () => {
        expect(src).toMatch(/berean_messages/);
    });

    test("collects bereanMemory", () => {
        expect(src).toMatch(/bereanMemory/);
    });

    test("collects prayerRequests", () => {
        expect(src).toMatch(/prayerRequests/);
    });

    test("collects posts", () => {
        expect(src).toMatch(/posts/);
    });

    test("signed URL is time-limited (not permanent)", () => {
        // Must pass an `expires` parameter to getSignedUrl.
        expect(src).toMatch(/expires:\s*Date\.now\(\)\s*\+/);
    });

    test("signed URL expires in ≤1 hour", () => {
        // SIGNED_URL_EXPIRY_MS should not exceed 3600000 ms (1 hour).
        const match = src.match(/SIGNED_URL_EXPIRY_MS\s*=\s*(\d+)/);
        expect(match).not.toBeNull();
        const expiryMs = parseInt(match![1], 10);
        expect(expiryMs).toBeLessThanOrEqual(3600000);
    });

    test("enforces per-user rate limit", () => {
        expect(src).toMatch(/enforceExportRateLimit|exportRateLimits/);
        expect(src).toMatch(/resource-exhausted/);
    });

    test("rate limit window is ≤24 hours", () => {
        const match = src.match(/RATE_LIMIT_WINDOW_MS\s*=\s*(\d+)/);
        expect(match).not.toBeNull();
        const windowMs = parseInt(match![1], 10);
        expect(windowMs).toBeLessThanOrEqual(24 * 60 * 60 * 1000);
    });

    test("writes audit log for compliance evidence", () => {
        expect(src).toMatch(/dataExportAuditLog/);
    });

    test("enforces App Check", () => {
        expect(src).toMatch(/enforceAppCheck:\s*true/);
    });

    test("strips internal system fields from export", () => {
        expect(src).toMatch(/STRIP_FIELDS|stripInternalFields/);
    });
});

// ── userAccountDeletionCascade.ts invariants ──────────────────────────────────

describe("userAccountDeletionCascade: Berean data included in hard-delete", () => {
    const src = readSrc("userAccountDeletionCascade.ts");

    test("cascade includes bereanMemory subcollection", () => {
        expect(src).toMatch(/bereanMemory/);
    });

    test("cascade includes bereanInsights subcollection", () => {
        expect(src).toMatch(/bereanInsights/);
    });

    test("cascade calls deleteBereanTopLevelData or equivalent", () => {
        expect(src).toMatch(/deleteBereanTopLevelData|berean_conversations/);
    });

    test("cascade deletes berean_messages", () => {
        expect(src).toMatch(/berean_messages/);
    });
});

// ── firestore.rules invariants ────────────────────────────────────────────────

describe("firestore.rules: berean collection isolation", () => {
    const rules = fs.readFileSync(
        path.join(__dirname, "../../../../firestore.rules"),
        "utf-8"
    );

    test("berean_conversations read is scoped to owner", () => {
        expect(rules).toMatch(/berean_conversations/);
        expect(rules).toMatch(/resource\.data\.userId\s*==\s*request\.auth\.uid/);
    });

    test("berean_conversations write is denied to clients", () => {
        // Expect allow write: if false near berean_conversations block.
        const convBlock = rules.substring(
            rules.indexOf("match /berean_conversations/"),
            rules.indexOf("match /berean_conversations/") + 500
        );
        expect(convBlock).toMatch(/allow\s+write\s*:\s*if\s+false/);
    });

    test("berean_messages write is denied to clients", () => {
        const msgBlock = rules.substring(
            rules.indexOf("match /berean_messages/"),
            rules.indexOf("match /berean_messages/") + 300
        );
        expect(msgBlock).toMatch(/allow\s+write\s*:\s*if\s+false/);
    });
});
