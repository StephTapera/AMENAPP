#!/usr/bin/env node
/*
 * Validates that Verification & Trust Remote Config starts fail-closed.
 */

import fs from "node:fs";
import path from "node:path";

const file = process.argv[2] || path.resolve("Backend/remote-config-verification-template.json");
const template = JSON.parse(fs.readFileSync(file, "utf8"));

const requiredFlags = [
    "verification_center_enabled",
    "identity_verification_enabled",
    "organization_verification_enabled",
    "role_verification_enabled",
    "creator_verification_enabled",
    "public_trust_badges_enabled",
    "impersonation_reports_enabled",
];

const errors = [];

for (const flag of requiredFlags) {
    const param = template.parameters?.[flag];
    if (!param) {
        errors.push(`Missing flag: ${flag}`);
        continue;
    }
    if (param.defaultValue?.value !== "false") {
        errors.push(`${flag} must default to false.`);
    }
}

const identity = template.parameters?.identity_verification_enabled;
if (identity?.conditionalValues) {
    for (const [condition, value] of Object.entries(identity.conditionalValues)) {
        if (value?.value !== "false") {
            errors.push(`identity_verification_enabled must remain false for ${condition} until live KYC smoke passes.`);
        }
    }
}

if (errors.length > 0) {
    console.error("Remote Config verification failed:");
    for (const error of errors) console.error(`- ${error}`);
    process.exit(1);
}

console.log("PASS: verification Remote Config template is fail-closed.");
