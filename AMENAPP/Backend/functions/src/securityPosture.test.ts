import * as fs from "fs";
import * as path from "path";

const srcRoot = path.resolve(__dirname);
const projectRoot = path.resolve(srcRoot, "../../..");

function readSource(relativePath: string): string {
  return fs.readFileSync(path.join(srcRoot, relativePath), "utf8");
}

function walkTypescriptFiles(dir: string): string[] {
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap((entry) => {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) return walkTypescriptFiles(fullPath);
    if (entry.isFile() && entry.name.endsWith(".ts") && !entry.name.endsWith(".test.ts")) {
      return [fullPath];
    }
    return [];
  });
}

describe("backend callable security posture", () => {
  it("does not leave gen2 callables on the unsafe default App Check setting", () => {
    const unsafeCallables = walkTypescriptFiles(srcRoot).flatMap((filePath) => {
      const source = fs.readFileSync(filePath, "utf8");
      const directUnsafe = source.includes("onCall(async");
      const configuredWithoutAppCheck = Array.from(source.matchAll(/onCall\(\s*\{[^)]*?\}/gs))
        .some((match) => !match[0].includes("enforceAppCheck: true"));
      return directUnsafe || configuredWithoutAppCheck ? [path.relative(srcRoot, filePath)] : [];
    });

    expect(unsafeCallables).toEqual([]);
  });

  it("keeps v1 smart attachment callables behind platform App Check enforcement", () => {
    const source = readSource("smartAttachments.ts");
    expect(source).toContain("functions.runWith({enforceAppCheck: true}).https.onCall");
    expect(source).not.toContain("functions.https.onCall");
  });
});

describe("trust and safety report taxonomy", () => {
  it("allows explicit child safety and exploitation report reasons in Firestore rules", () => {
    const rules = fs.readFileSync(path.join(projectRoot, "firestore.deploy.rules"), "utf8");
    const requiredReasons = [
      "child_safety",
      "csam",
      "grooming",
      "online_enticement",
      "sexual_exploitation",
      "sex_trafficking",
      "sextortion",
      "prostitution_facilitation",
      "pornography",
      "non_consensual_intimate_imagery",
      "deepfake_sexual_content",
      "sexualized_minor",
      "unsolicited_obscene_material_to_child",
    ];

    for (const reason of requiredReasons) {
      expect(rules).toContain(`'${reason}'`);
    }
  });
});
