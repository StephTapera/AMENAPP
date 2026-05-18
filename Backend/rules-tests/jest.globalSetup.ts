/**
 * jest.globalSetup.ts
 *
 * Runs once before any rules-test suite. Three responsibilities:
 *
 *  1. Point the Firebase Rules SDK at the local Firestore emulator
 *     (assumed already running on 127.0.0.1:8080).
 *
 *  2. Verify the emulator is actually reachable before tests start.
 *     If it's not, fail fast with the exact command the developer
 *     needs to run — instead of letting every test fail with a
 *     confusing `ECONNREFUSED 127.0.0.1:8080`.
 *
 *  3. Regenerate AMENAPP/firestore.deploy.rules from the canonical
 *     source AMENAPP/firestore 18.rules by running scripts/strip-rules.js.
 *     This guarantees the rules tests always exercise the same rules
 *     content that `firebase deploy` will publish — closing the
 *     "tests pass but deploy fails because deploy.rules is stale" gap.
 *
 * Phase P1-5: all rules tests target firestore.deploy.rules going
 * forward, and this hook keeps the artifact fresh.
 */

import { execFileSync } from "child_process";
import * as fs from "fs";
import * as http from "http";
import * as path from "path";

const REPO_ROOT = path.resolve(__dirname, "../..");
const STRIP_SCRIPT = path.join(REPO_ROOT, "scripts", "strip-rules.js");
const SRC_RULES = path.join(REPO_ROOT, "AMENAPP", "firestore 18.rules");
const DST_RULES = path.join(REPO_ROOT, "AMENAPP", "firestore.deploy.rules");

const EMULATOR_HOST = "127.0.0.1";
const FIRESTORE_PORT = 8080;
const DATABASE_PORT = 9000;
const STORAGE_PORT = 9199;

/**
 * Returns true if a Firebase emulator is listening on the given port.
 * The Firestore emulator answers GET / with `{"version":"..."}`; we
 * don't care about the body — we only care that a TCP connect succeeds
 * and HTTP responds within a short timeout.
 */
function isEmulatorReachable(port: number): Promise<boolean> {
    return new Promise((resolve) => {
        const req = http.request(
            {
                host: EMULATOR_HOST,
                port,
                method: "GET",
                path: "/",
                timeout: 1500,
            },
            (res) => {
                res.resume();
                resolve(true);
            }
        );
        req.on("error", () => resolve(false));
        req.on("timeout", () => {
            req.destroy();
            resolve(false);
        });
        req.end();
    });
}

const START_COMMAND =
    "firebase emulators:start --only firestore,database,storage";
const EXEC_COMMAND =
    'firebase emulators:exec --only firestore,database,storage "cd Backend/rules-tests && npm test"';

function emulatorMissingMessage(missingPorts: number[]): string {
    const portList = missingPorts.map((p) => String(p)).join(", ");
    return [
        "",
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
        "  Firebase emulator is not running.",
        `  Could not reach ${EMULATOR_HOST} on port(s): ${portList}.`,
        "",
        "  Start the emulator in another terminal:",
        `      ${START_COMMAND}`,
        "",
        "  Or run everything in one command:",
        `      ${EXEC_COMMAND}`,
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
        "",
    ].join("\n");
}

export default async function globalSetup() {
    process.env.FIRESTORE_EMULATOR_HOST = `${EMULATOR_HOST}:${FIRESTORE_PORT}`;
    process.env.FIREBASE_DATABASE_EMULATOR_HOST = `${EMULATOR_HOST}:${DATABASE_PORT}`;
    process.env.FIREBASE_STORAGE_EMULATOR_HOST = `${EMULATOR_HOST}:${STORAGE_PORT}`;

    // ── 1. Verify the rules source / strip script exist. ──────────────
    if (!fs.existsSync(STRIP_SCRIPT)) {
        throw new Error(
            `Rules strip script not found at ${STRIP_SCRIPT}. ` +
                `Cannot regenerate firestore.deploy.rules from source.`
        );
    }
    if (!fs.existsSync(SRC_RULES)) {
        throw new Error(
            `Canonical rules source not found at ${SRC_RULES}.`
        );
    }

    // ── 2. Regenerate the deployed artifact from the canonical source. ─
    execFileSync("node", [STRIP_SCRIPT], {
        cwd: REPO_ROOT,
        stdio: "inherit",
    });
    if (!fs.existsSync(DST_RULES)) {
        throw new Error(
            `strip-rules.js did not produce ${DST_RULES}.`
        );
    }

    // ── 3. Pre-flight: confirm the emulator is reachable. ─────────────
    //    Without this, every test in every suite fails with a
    //    confusing ECONNREFUSED. We probe Firestore (required) plus
    //    RTDB and Storage (only if their tests are part of this run,
    //    but probing is cheap and the message is more useful).
    const probes = await Promise.all([
        isEmulatorReachable(FIRESTORE_PORT).then((ok) =>
            ok ? null : FIRESTORE_PORT
        ),
        isEmulatorReachable(DATABASE_PORT).then((ok) =>
            ok ? null : DATABASE_PORT
        ),
        isEmulatorReachable(STORAGE_PORT).then((ok) =>
            ok ? null : STORAGE_PORT
        ),
    ]);

    // Firestore is mandatory for every rules suite in this directory.
    if (probes[0] !== null) {
        const missing = probes.filter((p): p is number => p !== null);
        throw new Error(emulatorMissingMessage(missing));
    }

    // RTDB / Storage are optional — only the matching suites need them.
    // Warn (don't throw) so a developer running only the Firestore
    // suites can still proceed with just the Firestore emulator up.
    const optionalMissing = probes.slice(1).filter((p): p is number => p !== null);
    if (optionalMissing.length > 0) {
        // eslint-disable-next-line no-console
        console.warn(
            `[jest.globalSetup] Optional emulator port(s) ${optionalMissing.join(
                ", "
            )} unreachable — RTDB / Storage rules suites will fail. ` +
                `Start them with: ${START_COMMAND}`
        );
    }
}
