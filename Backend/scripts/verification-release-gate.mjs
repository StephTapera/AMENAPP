#!/usr/bin/env node
/*
 * Final release gate for Amen Verification & Trust.
 *
 * This script does not pretend to run manual/provider/device checks itself.
 * It verifies that those checks have been executed and attested in a checked-in
 * or CI-provided JSON file.
 *
 * Usage:
 *   node Backend/scripts/verification-release-gate.mjs \
 *     --results Docs/VerificationTrustQAResults.staging.json
 */

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const args = process.argv.slice(2);
const resultsArgIndex = args.indexOf("--results");
const resultsPath = resultsArgIndex >= 0
    ? args[resultsArgIndex + 1]
    : "Docs/VerificationTrustQAResults.template.json";

const repoRoot = process.cwd();
const resolvedResultsPath = path.resolve(repoRoot, resultsPath);
const remoteConfigCheck = path.resolve(repoRoot, "Backend/scripts/verify-verification-remote-config.mjs");

const requiredChecks = [
    "liveProviderSmoke",
    "providerWebhookApproval",
    "providerWebhookRejection",
    "providerWebhookIdempotency",
    "adminReviewerE2E",
    "broadSurfaceQA",
    "remoteConfigRollout",
    "dataBackfill",
    "accessibilityDeviceQA",
    "noRawIdStorageConfirmed",
    "clientSpoofingBlockedConfirmed",
];

function fail(message) {
    console.error(`NO-GO: ${message}`);
    process.exit(1);
}

function runNodeScript(scriptPath) {
    const result = spawnSync(process.execPath, [scriptPath], {
        cwd: repoRoot,
        encoding: "utf8",
    });
    if (result.status !== 0) {
        process.stderr.write(result.stderr);
        process.stdout.write(result.stdout);
        fail(`${path.basename(scriptPath)} failed.`);
    }
}

function loadResults() {
    if (!fs.existsSync(resolvedResultsPath)) {
        fail(`QA results file not found: ${resultsPath}`);
    }

    const raw = fs.readFileSync(resolvedResultsPath, "utf8");
    try {
        return JSON.parse(raw);
    } catch (error) {
        fail(`QA results file is not valid JSON: ${error.message}`);
    }
}

runNodeScript(remoteConfigCheck);

const results = loadResults();
const missing = [];

for (const check of requiredChecks) {
    const entry = results.checks?.[check];
    if (!entry || entry.status !== "pass") {
        missing.push(check);
    }
    if (entry?.status === "pass" && (!entry.evidence || String(entry.evidence).trim().length === 0)) {
        missing.push(`${check} evidence`);
    }
}

if (results.environment !== "staging" && results.environment !== "production") {
    fail("environment must be 'staging' or 'production'.");
}

if (!results.reviewedBy || !results.reviewedAt) {
    fail("reviewedBy and reviewedAt are required.");
}

if (missing.length > 0) {
    console.error("Missing or incomplete checks:");
    for (const check of missing) console.error(`- ${check}`);
    fail("Verification & Trust release gate did not pass.");
}

console.log("GO: Verification & Trust production release gate passed.");
