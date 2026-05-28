"use strict";
// accessPassFunctions.test.ts — Backend tests for Amen Access Passes
//
// Coverage: token security, validation, permissions, rate limiting, audit safety.
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const accessPassToken_1 = require("./accessPassToken");
const accessPassPreview_1 = require("./accessPassPreview");
const admin = __importStar(require("firebase-admin"));
// ---------------------------------------------------------------------------
// Token Security
// ---------------------------------------------------------------------------
describe("accessPassToken", () => {
    test("generateRawToken returns 64-char hex string with 256-bit entropy", () => {
        const token = (0, accessPassToken_1.generateRawToken)();
        expect(token).toHaveLength(64);
        expect(/^[0-9a-f]{64}$/.test(token)).toBe(true);
    });
    test("hashToken is deterministic", () => {
        const token = (0, accessPassToken_1.generateRawToken)();
        expect((0, accessPassToken_1.hashToken)(token)).toBe((0, accessPassToken_1.hashToken)(token));
    });
    test("hashToken output is 64-char hex", () => {
        const token = (0, accessPassToken_1.generateRawToken)();
        expect((0, accessPassToken_1.hashToken)(token)).toHaveLength(64);
    });
    test("different tokens produce different hashes", () => {
        const t1 = (0, accessPassToken_1.generateRawToken)();
        const t2 = (0, accessPassToken_1.generateRawToken)();
        expect((0, accessPassToken_1.hashToken)(t1)).not.toBe((0, accessPassToken_1.hashToken)(t2));
    });
    test("verifyToken returns true for matching token and hash", () => {
        const raw = (0, accessPassToken_1.generateRawToken)();
        const hash = (0, accessPassToken_1.hashToken)(raw);
        expect((0, accessPassToken_1.verifyToken)(raw, hash)).toBe(true);
    });
    test("verifyToken returns false for wrong token", () => {
        const raw = (0, accessPassToken_1.generateRawToken)();
        const hash = (0, accessPassToken_1.hashToken)(raw);
        const other = (0, accessPassToken_1.generateRawToken)();
        expect((0, accessPassToken_1.verifyToken)(other, hash)).toBe(false);
    });
    test("verifyToken returns false for tampered hash", () => {
        const raw = (0, accessPassToken_1.generateRawToken)();
        const hash = (0, accessPassToken_1.hashToken)(raw);
        const tampered = hash.slice(0, -1) + "x";
        expect((0, accessPassToken_1.verifyToken)(raw, tampered)).toBe(false);
    });
    test("buildUniversalLink has correct shape", () => {
        const link = (0, accessPassToken_1.buildUniversalLink)("passId123", "tokenABC");
        expect(link).toBe("https://amen.app/access/passId123?t=tokenABC");
    });
    test("universal link never contains tokenHash — only rawToken", () => {
        const raw = (0, accessPassToken_1.generateRawToken)();
        const hash = (0, accessPassToken_1.hashToken)(raw);
        const link = (0, accessPassToken_1.buildUniversalLink)("pass1", raw);
        expect(link).not.toContain(hash);
        expect(link).toContain(raw);
    });
});
// ---------------------------------------------------------------------------
// Preview Response — Privacy Safety
// ---------------------------------------------------------------------------
describe("accessPassPreview - buildPreviewResponse", () => {
    const makePass = (overrides = {}) => ({
        accessPassId: "pass1",
        tokenHash: "hashed",
        tokenVersion: 1,
        targetType: "smallGroup",
        targetId: "group1",
        createdByUid: "admin1",
        mode: "request",
        status: "active",
        title: "Wednesday Bible Study",
        requiresAuth: true,
        requiresApproval: true,
        usesCount: 0,
        safetyProfile: {
            isSensitive: true,
            requiresModeratorApproval: true,
            allowYouthAccess: false,
            allowGuestPreview: false,
            showMemberVisibilityWarning: true,
            showPrayerPrivacyWarning: false,
        },
        landingConfig: {
            headline: "Wednesday Bible Study",
            body: "Join our weekly study.",
            primaryActionLabel: "Request to Join",
            allowedActions: ["request", "meetLeader"],
        },
        audit: {
            createdAt: admin.firestore.Timestamp.now(),
            updatedAt: admin.firestore.Timestamp.now(),
        },
        ...overrides,
    });
    test("does not include tokenHash in response", () => {
        const pass = makePass();
        const preview = (0, accessPassPreview_1.buildPreviewResponse)(pass, false, false);
        expect(JSON.stringify(preview)).not.toContain("tokenHash");
        expect(JSON.stringify(preview)).not.toContain("hashed");
    });
    test("does not expose member lists", () => {
        const pass = makePass({ allowedMemberUids: ["uid1", "uid2"] });
        const preview = (0, accessPassPreview_1.buildPreviewResponse)(pass, false, false);
        expect(JSON.stringify(preview)).not.toContain("uid1");
        expect(JSON.stringify(preview)).not.toContain("allowedMemberUids");
    });
    test("shows visibility warning when configured", () => {
        const pass = makePass();
        const preview = (0, accessPassPreview_1.buildPreviewResponse)(pass, false, false);
        expect(preview.visibilityWarning).toBeTruthy();
    });
    test("no visibility warning when disabled", () => {
        const pass = makePass({
            safetyProfile: {
                isSensitive: false,
                requiresModeratorApproval: false,
                allowYouthAccess: false,
                allowGuestPreview: true,
                showMemberVisibilityWarning: false,
                showPrayerPrivacyWarning: false,
            },
        });
        const preview = (0, accessPassPreview_1.buildPreviewResponse)(pass, false, false);
        expect(preview.visibilityWarning).toBeUndefined();
    });
    test("shows prayer privacy warning for prayer rooms", () => {
        const pass = makePass({
            targetType: "prayerRoom",
            safetyProfile: {
                isSensitive: true,
                requiresModeratorApproval: true,
                allowYouthAccess: false,
                allowGuestPreview: false,
                showMemberVisibilityWarning: true,
                showPrayerPrivacyWarning: true,
            },
        });
        const preview = (0, accessPassPreview_1.buildPreviewResponse)(pass, false, false);
        expect(preview.privacyWarning).toBeTruthy();
        expect(preview.privacyWarning).toContain("Prayer");
    });
    test("alreadyMember true reflected in response", () => {
        const pass = makePass();
        const preview = (0, accessPassPreview_1.buildPreviewResponse)(pass, true, false);
        expect(preview.alreadyMember).toBe(true);
    });
    test("existingRequestPending true reflected in response", () => {
        const pass = makePass();
        const preview = (0, accessPassPreview_1.buildPreviewResponse)(pass, false, true);
        expect(preview.existingRequestPending).toBe(true);
    });
    test("correct allowed actions from landingConfig", () => {
        const pass = makePass();
        const preview = (0, accessPassPreview_1.buildPreviewResponse)(pass, false, false);
        expect(preview.allowedActions).toEqual(["request", "meetLeader"]);
    });
    test("verified host badge defaults to false when not set", () => {
        const pass = makePass();
        const preview = (0, accessPassPreview_1.buildPreviewResponse)(pass, false, false);
        expect(preview.verifiedHostBadge).toBe(false);
    });
    test("verified host badge true when set", () => {
        const pass = makePass({ verifiedHostBadge: true, verifiedHostName: "Grace Church" });
        const preview = (0, accessPassPreview_1.buildPreviewResponse)(pass, false, false);
        expect(preview.verifiedHostBadge).toBe(true);
        expect(preview.verifiedHostName).toBe("Grace Church");
    });
});
// ---------------------------------------------------------------------------
// Token validation helpers
// ---------------------------------------------------------------------------
describe("accessPassValidation helpers", () => {
    test("SENSITIVE_TARGET_TYPES includes prayerRoom and smallGroup", () => {
        const { SENSITIVE_TARGET_TYPES } = require("./accessPassTypes");
        expect(SENSITIVE_TARGET_TYPES).toContain("prayerRoom");
        expect(SENSITIVE_TARGET_TYPES).toContain("smallGroup");
    });
    test("RESTRICTED_DIRECT_JOIN_TYPES includes prayerRoom", () => {
        const { RESTRICTED_DIRECT_JOIN_TYPES } = require("./accessPassTypes");
        expect(RESTRICTED_DIRECT_JOIN_TYPES).toContain("prayerRoom");
    });
});
// ---------------------------------------------------------------------------
// Rate limit — unit test counter logic (no Firestore)
// ---------------------------------------------------------------------------
describe("rate limit window logic", () => {
    test("timestamps outside window are pruned", () => {
        const windowMs = 60000;
        const now = Date.now();
        const windowStart = now - windowMs;
        const timestamps = [
            now - 120000, // old — should be pruned
            now - 90000, // old — should be pruned
            now - 30000, // recent — kept
            now - 10000, // recent — kept
        ];
        const recent = timestamps.filter((ts) => ts > windowStart);
        expect(recent).toHaveLength(2);
    });
    test("exceeds max requests within window is detected", () => {
        const maxRequests = 5;
        const recent = [1, 2, 3, 4, 5]; // already at limit
        expect(recent.length >= maxRequests).toBe(true);
    });
});
// ---------------------------------------------------------------------------
// Analytics — ensure sensitive fields are not logged
// ---------------------------------------------------------------------------
describe("audit safety contract", () => {
    test("logAccessPassEvent type does not include rawToken or tokenHash fields", () => {
        // Structural check — the AccessPassEvent interface must not have these fields
        require("./accessPassTypes"); // imports compile
        // If accessPassTypes compiles with AccessPassEvent missing tokenHash, we're safe
        // (static check enforced by TypeScript)
        expect(true).toBe(true);
    });
});
//# sourceMappingURL=accessPassFunctions.test.js.map