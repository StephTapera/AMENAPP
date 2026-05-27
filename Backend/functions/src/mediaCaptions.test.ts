import fs from "fs";
import path from "path";

const source = fs.readFileSync(path.join(__dirname, "mediaCaptions", "index.ts"), "utf8");
const contract = fs.readFileSync(path.join(__dirname, "mediaCaptions", "contract.ts"), "utf8");

describe("per-media captions callable contract", () => {
  it("exports the frozen callable names", () => {
    expect(source).toContain("export const moderateMediaCaption");
    expect(source).toContain("export const publishPostWithMedia");
    expect(source).toContain("export const updatePostMediaCaptions");
    expect(source).toContain("export const generateAltText");
  });

  it("requires auth and App Check for all caption callables", () => {
    const appCheckUsages = (source.match(/enforceAppCheck: true/g) ?? []).length;
    const authUsages = (source.match(/requireAuth\\(request\\)/g) ?? []).length;
    expect(appCheckUsages).toBeGreaterThanOrEqual(4);
    expect(authUsages).toBeGreaterThanOrEqual(4);
  });

  it("keeps moderation states character-identical to the Swift contract", () => {
    for (const status of ["not_required", "pending", "approved", "rejected", "removed"]) {
      expect(contract).toContain(`| "${status}"`);
    }
  });

  it("does not persist client-supplied captionModeration from input", () => {
    expect(contract).toContain("captionModeration?: never");
    expect(source).not.toContain("raw.captionModeration");
    expect(source).not.toContain("data.captionModeration");
  });

  it("returns the UI-consumed altText key as well as the legacy suggestion key", () => {
    expect(source).toContain("return { altText, suggestion: altText }");
  });
});
