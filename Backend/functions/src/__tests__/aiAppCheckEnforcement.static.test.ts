/**
 * aiAppCheckEnforcement.static.test.ts
 *
 * Phase P1-7 — static-source CI regression test.
 *
 * Fails the build if any deployed AI Cloud Function callable file
 * contains `enforceAppCheck: false`. Allowed exceptions are limited to
 * a small, explicit allowlist of pre-auth bootstrap / scheduler
 * callables that intentionally do not require App Check.
 *
 * Scope of files scanned:
 *   - Backend/functions/src/**.ts (the modern "creator" codebase)
 *   - functions/*.js + functions/src/heyFeed/callable.ts (the legacy
 *     "default" codebase)
 *
 * This test reads source files only — it does not load Firebase
 * Functions at runtime — so it is safe under jest's standard config
 * and adds <100 ms to the suite.
 */

import * as fs from "fs";
import * as path from "path";

// ── Configuration ────────────────────────────────────────────────────────────

/**
 * Repo root inferred relative to this test file:
 *   Backend/functions/src/__tests__/THIS_FILE.ts
 *   → ../../../../ is the repo root.
 */
const REPO_ROOT = path.resolve(__dirname, "../../../..");

/**
 * Roots that contain deployed Cloud Functions source.
 * Both the legacy "default" codebase (root `functions/`) and the modern
 * "creator" codebase (`Backend/functions/src/`) are scanned.
 */
const SCAN_ROOTS = [
    path.join(REPO_ROOT, "functions"),
    path.join(REPO_ROOT, "Backend", "functions", "src"),
];

/**
 * Heuristic — a file is considered an "AI callable surface" if it
 * mentions any of these provider/feature tokens. This is intentionally
 * broad: we'd rather flag a non-AI file than miss an AI one.
 */
const AI_TOKEN_RE = /\b(openAI|OpenAI|Anthropic|claude|whisper|gemini|berean|Berean|heyFeed|heyfeed|aiPrompt|llm|LLM|gpt-|sonnet|haiku|opus)\b/;

/**
 * Files (relative to REPO_ROOT) that are explicitly allowed to declare
 * `enforceAppCheck: false`. These are pre-auth bootstrap callables, the
 * scheduler runtime, and admin bootstrap. They are NOT AI surfaces.
 *
 * Adding a new entry here must be justified in code review.
 */
const PRE_AUTH_ALLOWLIST = new Set<string>([
    "functions/authenticationHelpers.js",
    "functions/adminClaims.js",
    "functions/maintenanceSchedulers.js",
]);

/**
 * Directories/files we never walk into.
 */
const SKIP_DIRS = new Set<string>([
    "node_modules",
    "lib",
    "dist",
    "build",
    ".git",
    "__tests__",
    "__mocks__",
    "tests",
    "test",
    "coverage",
]);

const SKIP_FILE_SUFFIXES = [
    ".test.ts",
    ".test.js",
    ".spec.ts",
    ".spec.js",
    ".d.ts",
];

// ── Helpers ──────────────────────────────────────────────────────────────────

function walk(root: string, out: string[] = []): string[] {
    let entries: fs.Dirent[];
    try {
        entries = fs.readdirSync(root, { withFileTypes: true });
    } catch {
        // Root doesn't exist (some checkouts may not have both codebases).
        return out;
    }
    for (const ent of entries) {
        const full = path.join(root, ent.name);
        if (ent.isDirectory()) {
            if (SKIP_DIRS.has(ent.name)) continue;
            walk(full, out);
        } else if (ent.isFile()) {
            if (!/\.(ts|js)$/.test(ent.name)) continue;
            if (SKIP_FILE_SUFFIXES.some((s) => ent.name.endsWith(s))) continue;
            out.push(full);
        }
    }
    return out;
}

function relFromRepo(absPath: string): string {
    return path.relative(REPO_ROOT, absPath);
}

/**
 * True if `enforceAppCheck: false` appears textually in the source.
 * Tolerates one or more spaces between key, colon, and value.
 */
function hasEnforceAppCheckFalse(src: string): boolean {
    return /enforceAppCheck\s*:\s*false\b/.test(src);
}

/**
 * True if the file looks like it touches an AI/LLM surface.
 */
function looksAIRelated(src: string): boolean {
    return AI_TOKEN_RE.test(src);
}

// ── The test ─────────────────────────────────────────────────────────────────

describe("AI callable App Check enforcement (static)", () => {
    const allScannedFiles: string[] = [];
    for (const root of SCAN_ROOTS) {
        walk(root, allScannedFiles);
    }

    test("scan picks up a non-trivial number of files", () => {
        // Sanity guard: if this regression test ever scans zero files
        // (because the SCAN_ROOTS path is wrong or skip rules are too
        // greedy), the suite would silently pass. Refuse that.
        expect(allScannedFiles.length).toBeGreaterThan(20);
    });

    test("no AI callable declares enforceAppCheck:false", () => {
        const violations: Array<{ file: string; lineNumbers: number[] }> = [];

        for (const file of allScannedFiles) {
            const src = fs.readFileSync(file, "utf8");
            if (!hasEnforceAppCheckFalse(src)) continue;

            const rel = relFromRepo(file);

            // Allowlisted pre-auth bootstrap files: skip without complaint.
            if (PRE_AUTH_ALLOWLIST.has(rel)) continue;

            // If `enforceAppCheck: false` is present AND the file looks
            // AI-related, that is a hard failure.
            if (looksAIRelated(src)) {
                const lineNumbers: number[] = [];
                src.split("\n").forEach((line, idx) => {
                    if (/enforceAppCheck\s*:\s*false\b/.test(line)) {
                        lineNumbers.push(idx + 1);
                    }
                });
                violations.push({ file: rel, lineNumbers });
                continue;
            }

            // Non-AI file with enforceAppCheck:false that is NOT in the
            // pre-auth allowlist. Treat as a violation too — every new
            // exception must be explicit.
            const lineNumbers: number[] = [];
            src.split("\n").forEach((line, idx) => {
                if (/enforceAppCheck\s*:\s*false\b/.test(line)) {
                    lineNumbers.push(idx + 1);
                }
            });
            violations.push({ file: rel, lineNumbers });
        }

        if (violations.length > 0) {
            const detail = violations
                .map((v) => `  - ${v.file}:${v.lineNumbers.join(",")}`)
                .join("\n");
            const msg =
                "Found enforceAppCheck:false in deployed callable file(s) " +
                "without explicit allowlist entry:\n" +
                detail +
                "\n\nIf this is intentional (pre-auth bootstrap), add the " +
                "file path to PRE_AUTH_ALLOWLIST in " +
                "aiAppCheckEnforcement.static.test.ts and justify in review.";
            throw new Error(msg);
        }

        expect(violations).toEqual([]);
    });

    test("AI callable files never accept data.userId / data.uid as identity", () => {
        // This is a softer check than App Check enforcement because some
        // files legitimately compare data.userId against the auth uid for
        // validation. We flag any line that assigns or returns from
        // data.userId/data.uid as if it were trusted identity.
        //
        // Pattern: `const uid = data.userId` / `const uid = data.uid` / etc.
        const TRUST_PATTERN =
            /\b(?:const|let|var)\s+\w+\s*=\s*(?:request\.)?data\.(uid|userId)\b/;

        const violations: Array<{ file: string; line: number; snippet: string }> = [];
        for (const file of allScannedFiles) {
            const src = fs.readFileSync(file, "utf8");
            if (!looksAIRelated(src)) continue;
            src.split("\n").forEach((line, idx) => {
                if (TRUST_PATTERN.test(line)) {
                    violations.push({
                        file: relFromRepo(file),
                        line: idx + 1,
                        snippet: line.trim().slice(0, 160),
                    });
                }
            });
        }

        if (violations.length > 0) {
            const detail = violations
                .map((v) => `  - ${v.file}:${v.line}  ${v.snippet}`)
                .join("\n");
            throw new Error(
                "AI callable assigns identity from client-supplied " +
                "data.userId/data.uid (must use context.auth.uid):\n" +
                detail
            );
        }
        expect(violations).toEqual([]);
    });
});
