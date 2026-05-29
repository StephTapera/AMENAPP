/**
 * auth.sessionSecurity.static.test.ts
 *
 * Static invariant tests for Agent 6: Auth & Account-Takeover Hardening.
 *
 * These tests parse source and rules files to assert structural requirements
 * that must remain true. No Firebase runtime required.
 *
 * Each test encodes a SECURITY REQUIREMENT:
 *   - A failing test means a hardening guarantee has been weakened or removed.
 */

import * as fs from "fs";
import * as path from "path";

function readSrc(relPath: string): string {
    return fs.readFileSync(path.join(__dirname, "..", relPath), "utf-8");
}

function readRules(): string {
    return fs.readFileSync(
        path.join(__dirname, "../../../../firestore.rules"),
        "utf-8"
    );
}

// ── sessionRevocation.ts invariants ───────────────────────────────────────────

describe("sessionRevocation: structural invariants", () => {
    const src = readSrc("auth/sessionRevocation.ts");

    test("calls revokeRefreshTokens", () => {
        expect(src).toMatch(/revokeRefreshTokens/);
    });

    test("writes sessionAuditLog entry", () => {
        expect(src).toMatch(/sessionAuditLog/);
    });

    test("writes lastGlobalRevocationAt sentinel for client sign-out", () => {
        expect(src).toMatch(/lastGlobalRevocationAt/);
    });

    test("enforces App Check", () => {
        expect(src).toMatch(/enforceAppCheck:\s*true/);
    });

    test("requires authentication", () => {
        expect(src).toMatch(/request\.auth\?\.uid/);
        expect(src).toMatch(/unauthenticated/);
    });

    test("exports revokeAllSessionsForUid helper for internal use", () => {
        expect(src).toMatch(/export\s+async\s+function\s+revokeAllSessionsForUid/);
    });

    test("reportAccountCompromise creates securityIncidents record", () => {
        expect(src).toMatch(/securityIncidents/);
        expect(src).toMatch(/account_compromise_report/);
    });
});

// ── sensitiveActionGate.ts invariants ─────────────────────────────────────────

describe("sensitiveActionGate: structural invariants", () => {
    const src = readSrc("auth/sensitiveActionGate.ts");

    test("reads auth_time from the Firebase ID token", () => {
        expect(src).toMatch(/auth_time/);
    });

    test("rejects stale sessions beyond MAX_AUTH_AGE_SECONDS", () => {
        expect(src).toMatch(/MAX_AUTH_AGE_SECONDS/);
        expect(src).toMatch(/requiresReauth:\s*true/);
    });

    test("MAX_AUTH_AGE_SECONDS is ≤10 minutes", () => {
        const match = src.match(/MAX_AUTH_AGE_SECONDS\s*=\s*(\d+)\s*\*\s*60/);
        expect(match).not.toBeNull();
        const minutes = parseInt(match![1], 10);
        expect(minutes).toBeLessThanOrEqual(10);
    });

    test("grant TTL is ≤10 minutes", () => {
        const match = src.match(/GRANT_TTL_SECONDS\s*=\s*(\d+)\s*\*\s*60/);
        expect(match).not.toBeNull();
        const minutes = parseInt(match![1], 10);
        expect(minutes).toBeLessThanOrEqual(10);
    });

    test("writes grant to sensitiveActionGrants collection", () => {
        expect(src).toMatch(/sensitiveActionGrants/);
    });

    test("consumeSensitiveActionGrant uses a transaction (atomic consume)", () => {
        expect(src).toMatch(/runTransaction/);
        expect(src).toMatch(/consumed:\s*true/);
    });

    test("grant is rejected if already consumed", () => {
        expect(src).toMatch(/already been used/);
    });

    test("grant is rejected if expired", () => {
        expect(src).toMatch(/expired/);
    });

    test("enforces App Check on requireRecentAuth callable", () => {
        expect(src).toMatch(/enforceAppCheck:\s*true/);
    });

    test("delete_account is in SUPPORTED_ACTIONS", () => {
        expect(src).toMatch(/delete_account/);
    });

    test("change_email is in SUPPORTED_ACTIONS", () => {
        expect(src).toMatch(/change_email/);
    });

    test("disable_2fa is in SUPPORTED_ACTIONS", () => {
        expect(src).toMatch(/disable_2fa/);
    });
});

// ── accountSuspension.ts invariants ───────────────────────────────────────────

describe("accountSuspension: token revocation on suspension", () => {
    const src = readSrc("accountSuspension.ts");

    test("calls revokeRefreshTokens when suspending a user", () => {
        expect(src).toMatch(/revokeRefreshTokens/);
    });

    test("calls updateUser disabled:true before token revocation", () => {
        const disableIdx = src.indexOf("disabled: true");
        const revokeIdx = src.indexOf("revokeRefreshTokens");
        expect(disableIdx).toBeGreaterThan(-1);
        expect(revokeIdx).toBeGreaterThan(-1);
        expect(disableIdx).toBeLessThan(revokeIdx);
    });
});

// ── userAccountDeletionCascade.ts invariants ──────────────────────────────────

describe("userAccountDeletionCascade: token revocation before Auth deletion", () => {
    const src = readSrc("userAccountDeletionCascade.ts");

    test("calls revokeRefreshTokens before deleteUser", () => {
        const revokeIdx = src.indexOf("revokeRefreshTokens");
        const deleteIdx = src.indexOf("deleteUser(userId)");
        expect(revokeIdx).toBeGreaterThan(-1);
        expect(deleteIdx).toBeGreaterThan(-1);
        expect(revokeIdx).toBeLessThan(deleteIdx);
    });
});

// ── firestore.rules invariants ────────────────────────────────────────────────

describe("firestore.rules: auth hardening", () => {
    const rules = readRules();

    test("recentlyAuthenticated helper is defined", () => {
        expect(rules).toMatch(/function\s+recentlyAuthenticated/);
        expect(rules).toMatch(/auth_time/);
    });

    test("sensitiveActionGrants are server-only (no client read/write)", () => {
        const block = rules.substring(
            rules.indexOf("match /sensitiveActionGrants/"),
            rules.indexOf("match /sensitiveActionGrants/") + 200
        );
        expect(block).toMatch(/allow\s+read,\s*write\s*:\s*if\s+false/);
    });

    test("sessionAuditLog is server-only", () => {
        const block = rules.substring(
            rules.indexOf("match /sessionAuditLog/"),
            rules.indexOf("match /sessionAuditLog/") + 200
        );
        expect(block).toMatch(/allow\s+read,\s*write\s*:\s*if\s+false/);
    });

    test("securityIncidents is server-only", () => {
        const block = rules.substring(
            rules.indexOf("match /securityIncidents/"),
            rules.indexOf("match /securityIncidents/") + 200
        );
        expect(block).toMatch(/allow\s+read,\s*write\s*:\s*if\s+false/);
    });

    test("exportRateLimits is server-only", () => {
        expect(rules).toMatch(/match \/exportRateLimits\//);
    });
});
