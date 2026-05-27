import * as fs from "fs";
import * as path from "path";

const SRC_ROOT = path.resolve(__dirname, "..");

function readSource(relativePath: string): string {
  return fs.readFileSync(path.join(SRC_ROOT, relativePath), "utf8");
}

describe("permissions integration source contract", () => {
  test("setDateOfBirth resolves permissions immediately after storing DOB", () => {
    const source = readSource("permissions/permissionsCallables.ts");

    expect(source).toContain("export const setDateOfBirth");
    expect(source).toContain(".collection(\"private\").doc(\"safety\")");
    expect(source).toContain("await writeResolvedPermissions(uid, resolved, account.ageTier)");
  });

  test("syncAgeTierClaim delegates to the permissions engine instead of writing partial claims", () => {
    const source = readSource("syncAgeTierClaim.ts");

    expect(source).toContain("resolvePermissions(account)");
    expect(source).toContain("writeResolvedPermissions(uid, resolved, account.ageTier)");
    expect(source).not.toContain("setCustomUserClaims");
  });

  test("permissions exports include callable and trigger entry points", () => {
    const source = readSource("index.ts");

    expect(source).toContain("setDateOfBirth");
    expect(source).toContain("./permissions/permissionsCallables");
    expect(source).toContain("onUserWrite");
    expect(source).toContain("dailyAgeTierPromotion");
    expect(source).toContain("./syncAgeTierClaim");
  });
});
