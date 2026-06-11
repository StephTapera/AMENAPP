/**
 * phoneAuthPii.test.js — GAP BOARD P0-2
 *
 * Proves phoneAuthRateLimit.js never persists or logs a raw E.164 phone number:
 *  - redactPhone() exposes only the last 4 digits
 *  - hashPhone() is deterministic, peppered, 64-hex, and irreversible-looking
 *  - the SOURCE contains no `.doc(phoneNumber)` and no `${phoneNumber}` template
 */
const fs = require("fs");
const path = require("path");
const {hashPhone, redactPhone} = require("../phoneAuthRateLimit");

const RAW = "+14155552671";

describe("P0-2 — phone PII protection", () => {
  test("redactPhone exposes only the last 4 digits", () => {
    expect(redactPhone(RAW)).toBe("***2671");
    expect(redactPhone(RAW)).not.toContain("415555");
    expect(redactPhone("12")).toBe("***");
    expect(redactPhone(null)).toBe("***");
  });

  test("hashPhone is deterministic, peppered, 64-hex, and not the raw number", () => {
    const h = hashPhone(RAW, "pepper-A");
    expect(h).toMatch(/^[0-9a-f]{64}$/);
    expect(h).toBe(hashPhone(RAW, "pepper-A")); // deterministic for a stable doc ID
    expect(h).not.toBe(hashPhone(RAW, "pepper-B")); // pepper actually matters
    expect(h).not.toContain("4155552671");
  });

  test("source never puts a raw phone number in a doc path or a log/template", () => {
    const src = fs.readFileSync(path.resolve(__dirname, "../phoneAuthRateLimit.js"), "utf8");
    expect(src).not.toMatch(/\.doc\(phoneNumber\)/); // no raw number as doc id
    expect(src).not.toMatch(/\$\{phoneNumber\}/); // no raw number in any template literal
    expect(src).toMatch(/\.doc\(phoneHash\)/); // hashed doc id is used
    expect(src).toMatch(/phoneHash,/); // hash is what gets stored
  });
});
