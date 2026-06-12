import * as fs from "fs";
import * as path from "path";

const src = path.join(__dirname, "..");

function read(relativePath: string): string {
    return fs.readFileSync(path.join(src, relativePath), "utf8");
}

describe("account lifecycle callable surface", () => {
    // P0-9 / P0-10: Verify that the deletion cascade covers all AI conversation stores.
    // This is a static source-level assertion: if any of these strings disappear from the
    // cascade source it means the collection was accidentally removed from deletion scope.
    test("P0-9 P0-10: deletion cascade includes all AI/Berean conversation collections", () => {
        const cascade = read("src/userAccountDeletionCascade.ts");
        // Root collections (P0-9)
        expect(cascade).toContain("aiBibleStudyConversations");
        expect(cascade).toContain("realtimeSessions");
        // User subcollections (P0-10)
        expect(cascade).toContain('"chatHistory"');
        expect(cascade).toContain('"bereanConversations"');
        // Subcollection cleanup for nested content
        expect(cascade).toContain('collection("messages")');
        expect(cascade).toContain('collection("analyticsEvents")');
        expect(cascade).toContain('collection("scriptureReferences")');
    });

    test("P0-9 P0-10: accountDeletion.js (Firestore trigger) covers same AI stores", () => {
        const trigger = fs.readFileSync(
            path.join(__dirname, "../../../functions/accountDeletion.js"),
            "utf8"
        );
        expect(trigger).toContain("aiBibleStudyConversations");
        expect(trigger).toContain("realtimeSessions");
        expect(trigger).toContain("'chatHistory'");
        expect(trigger).toContain("'bereanConversations'");
    });

    test("exports auth/account lifecycle callables used by iOS", () => {
        const index = read("index.ts");
        expect(index).toContain('export * from "./twoFactorAuth"');
        expect(index).toContain('export * from "./accountLifecycle"');
        expect(index).toContain('export * from "./userAccountDeletionCascade"');

        const twoFactor = read("twoFactorAuth.ts");
        [
            "request2FAOTP",
            "verify2FAOTP",
            "enableTwoFactor",
            "disableTwoFactor",
            "generateBackupCodes",
            "regenerateBackupCodes",
            "verifyBackupCode",
        ].forEach((name) => expect(twoFactor).toContain(`export const ${name}`));

        const account = read("accountLifecycle.ts");
        [
            "createAmenUserProfile",
            "deactivateAccount",
            "reactivateAccount",
            "requestAccountDeletion",
            "checkPhoneVerificationRateLimit",
            "reportPhoneVerificationFailure",
        ].forEach((name) => expect(account).toContain(`export const ${name}`));
    });

    test("backup codes are stored as hashes, not plaintext code fields", () => {
        const twoFactor = read("twoFactorAuth.ts");
        expect(twoFactor).toContain("backupCodeSalt");
        expect(twoFactor).toContain("codeHash");
        expect(twoFactor).not.toContain('code": code');
        expect(twoFactor).not.toContain("code: code");
    });
});
