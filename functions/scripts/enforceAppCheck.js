#!/usr/bin/env node
// enforceAppCheck.js
// Programmatically enables Firebase App Check enforcement for Cloud Functions
// (and optionally Firestore + Storage) via the Firebase App Check Management API.
//
// This replaces the manual Firebase Console → App Check → Enforce toggle.
//
// Usage:
//   FIREBASE_PROJECT=<your-project-id> node scripts/enforceAppCheck.js
//
// Auth: uses Application Default Credentials — run one of:
//   gcloud auth application-default login
//   OR set GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
//
// The service account needs the "Firebase App Check Admin" IAM role
// (roles/firebaseappcheck.admin) or "Editor" on the project.
//
// Dry-run (prints request but does NOT call API):
//   DRY_RUN=true FIREBASE_PROJECT=my-project node scripts/enforceAppCheck.js

"use strict";

const https = require("https");
const admin = require("firebase-admin");

const PROJECT = process.env.FIREBASE_PROJECT;
const DRY_RUN = process.env.DRY_RUN === "true";

if (!PROJECT) {
  console.error("[enforceAppCheck] ERROR: Set FIREBASE_PROJECT environment variable.");
  console.error("  Example: FIREBASE_PROJECT=my-amen-project node scripts/enforceAppCheck.js");
  process.exit(1);
}

// Services to enforce. Cloud Functions is the critical one.
// Remove entries you don't want to enforce yet.
const SERVICES_TO_ENFORCE = [
  "cloudfunctions.googleapis.com",   // All Cloud Functions (the main gate)
  "firestore.googleapis.com",        // Firestore direct client access
  // "storage.googleapis.com",       // Uncomment when Storage rules are App-Check-gated
];

admin.initializeApp({ projectId: PROJECT });

async function getAccessToken() {
  // firebase-admin's GoogleAuthLibrary credential exposes getAccessToken()
  const app = admin.app();
  // Access the underlying credential
  const credential = app.options.credential ?? admin.credential.applicationDefault();
  const tokenResponse = await credential.getAccessToken();
  return tokenResponse.access_token;
}

async function enforceService(token, serviceId) {
  const url = `https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT}/services/${encodeURIComponent(serviceId)}?updateMask=enforcementMode`;
  const body = JSON.stringify({ enforcementMode: "ENFORCED" });

  if (DRY_RUN) {
    console.log(`  [DRY RUN] PATCH ${url}`);
    console.log(`  Body: ${body}`);
    return { dryRun: true, serviceId };
  }

  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const req = https.request(
      {
        hostname: urlObj.hostname,
        path: urlObj.pathname + urlObj.search,
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${token}`,
          "Content-Length": Buffer.byteLength(body),
        },
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => { data += chunk; });
        res.on("end", () => {
          if (res.statusCode === 200) {
            const result = JSON.parse(data);
            resolve(result);
          } else {
            reject(new Error(`HTTP ${res.statusCode}: ${data}`));
          }
        });
      }
    );
    req.on("error", reject);
    req.write(body);
    req.end();
  });
}

async function getServiceStatus(token, serviceId) {
  const url = `https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT}/services/${encodeURIComponent(serviceId)}`;
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const req = https.request(
      {
        hostname: urlObj.hostname,
        path: urlObj.pathname,
        method: "GET",
        headers: { "Authorization": `Bearer ${token}` },
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => { data += chunk; });
        res.on("end", () => {
          if (res.statusCode === 200) {
            resolve(JSON.parse(data));
          } else {
            // 404 is fine — service has never been configured (defaults to UNENFORCED)
            resolve({ name: serviceId, enforcementMode: "UNENFORCED (not yet configured)" });
          }
        });
      }
    );
    req.on("error", reject);
    req.end();
  });
}

async function run() {
  console.log(`[enforceAppCheck] Project: ${PROJECT}${DRY_RUN ? " (DRY RUN)" : ""}\n`);

  let token;
  try {
    token = await getAccessToken();
  } catch (err) {
    console.error("[enforceAppCheck] Failed to obtain access token.");
    console.error("  Make sure you are authenticated:");
    console.error("    gcloud auth application-default login");
    console.error("  OR set GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa.json");
    console.error("  Error:", err.message);
    process.exit(1);
  }

  // Print current state
  console.log("Current enforcement state:");
  for (const svc of SERVICES_TO_ENFORCE) {
    try {
      const status = await getServiceStatus(token, svc);
      const mode = status.enforcementMode ?? "UNENFORCED";
      const icon = mode === "ENFORCED" ? "✓" : mode === "UNENFORCED" ? "✗" : "?";
      console.log(`  ${icon} ${svc}: ${mode}`);
    } catch (e) {
      console.log(`  ? ${svc}: (could not fetch — ${e.message})`);
    }
  }

  console.log("\nEnforcing App Check...");

  let allOk = true;
  for (const svc of SERVICES_TO_ENFORCE) {
    try {
      const result = await enforceService(token, svc);
      const mode = result.enforcementMode ?? result.dryRun ? "DRY_RUN" : "?";
      console.log(`  ✓ ${svc}: ${mode}`);
    } catch (err) {
      console.error(`  ✗ ${svc}: FAILED — ${err.message}`);
      allOk = false;
    }
  }

  if (!allOk) {
    console.error("\n[enforceAppCheck] One or more services failed. Check IAM permissions.");
    console.error("  Required role: roles/firebaseappcheck.admin (or Editor)");
    process.exit(1);
  }

  console.log("\n[enforceAppCheck] Done. App Check is now ENFORCED.");
  console.log("  iOS client: App Attest (real device) + Debug token (simulator) — already configured.");
  console.log("  NOTE: Register your simulator debug token in Firebase Console → App Check → Apps → Debug tokens.");
  process.exit(0);
}

run().catch((err) => {
  console.error("[enforceAppCheck] FATAL:", err);
  process.exit(1);
});
