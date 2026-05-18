import * as fs from "fs";
import * as path from "path";

const srcRoot = path.resolve(__dirname);
const projectRoot = path.resolve(srcRoot, "../../..");

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

function callableSnippets(source: string): string[] {
    const snippets: string[] = [];
    const pattern = /(?:functions\.https\.|functions\.)?onCall\((.{0,320}?)async/gs;
    let match = pattern.exec(source);
    while (match) {
        snippets.push(match[0]);
        match = pattern.exec(source);
    }
    return snippets;
}

describe("backend callable security posture", () => {
    it("keeps callable functions behind platform App Check enforcement", () => {
        const unsafe = walkTypescriptFiles(srcRoot).flatMap((filePath) => {
            const source = fs.readFileSync(filePath, "utf8");
            const snippets = callableSnippets(source).filter((snippet) => {
                const prefixStart = Math.max(0, source.indexOf(snippet) - 100);
                const prefix = source.slice(prefixStart, source.indexOf(snippet));
                return !snippet.includes("enforceAppCheck: true") &&
                    !prefix.includes("runWith({ enforceAppCheck: true })");
            });
            return snippets.length > 0 ? [path.relative(srcRoot, filePath)] : [];
        });

        expect(unsafe).toEqual([]);
    });

    it("does not use effectively permanent signed URLs", () => {
        const offenders = walkTypescriptFiles(srcRoot).filter((filePath) => {
            const source = fs.readFileSync(filePath, "utf8");
            return source.includes("03-01-2500");
        });

        expect(offenders).toEqual([]);
    });
});

describe("trust and safety report taxonomy", () => {
    it("allows explicit child safety and exploitation report reasons in Firestore rules", () => {
        const rules = fs.readFileSync(path.join(projectRoot, "AMENAPP/firestore.deploy.rules"), "utf8");
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
