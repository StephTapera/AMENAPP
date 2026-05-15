import * as fs from "fs";
import * as path from "path";

const src = path.join(__dirname, "..");

function read(relativePath: string): string {
    return fs.readFileSync(path.join(src, relativePath), "utf8");
}

describe("account lifecycle callable surface", () => {
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
