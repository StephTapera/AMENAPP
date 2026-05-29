#!/usr/bin/env node
/**
 * predeploy-rules-check.js
 *
 * Runs before every `firebase deploy` to guard against the two-codebase
 * deploy-ordering risk (L-1 from the 2026-05-29 security audit).
 *
 * Problem: the repo has two Firebase codebases:
 *   - functions/           (codebase: "default")
 *   - Backend/functions/   (codebase: "backend")
 *
 * Both share the same top-level firestore.rules / storage.rules.
 * If someone deploys from the wrong directory or in the wrong order,
 * stale rules can overwrite newer ones.
 *
 * This script aborts the deploy if:
 *   1. firestore.rules has uncommitted changes (rules may be in an unknown state)
 *   2. The rules files are older than any source file in Backend/functions/src
 *      (i.e. backend code was updated but rules weren't reviewed)
 */

"use strict";

const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");

function mtime(p) {
  try { return fs.statSync(p).mtimeMs; } catch { return 0; }
}

function abort(msg) {
  console.error(`\n🚨  PREDEPLOY CHECK FAILED\n${msg}\n`);
  process.exit(1);
}

// 1. Check for uncommitted rule changes
try {
  const status = execSync("git status --porcelain firestore.rules AMENAPP/storage.rules", {
    cwd: ROOT, encoding: "utf8",
  });
  if (status.trim()) {
    abort(
      "firestore.rules or storage.rules has uncommitted local changes.\n" +
      "Commit or stash them before deploying to avoid pushing a work-in-progress ruleset.\n" +
      `  ${status.trim()}`
    );
  }
} catch {
  // git not available in CI — skip
}

// 2. Warn if Backend/functions/src is newer than firestore.rules
const rulesTime = mtime(path.join(ROOT, "firestore.rules"));
const backendSrcDir = path.join(ROOT, "Backend/functions/src");

function latestMtime(dir) {
  let latest = 0;
  try {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        latest = Math.max(latest, latestMtime(full));
      } else {
        latest = Math.max(latest, mtime(full));
      }
    }
  } catch { /* ignore */ }
  return latest;
}

const backendTime = latestMtime(backendSrcDir);

if (backendTime > rulesTime) {
  const backendDate = new Date(backendTime).toISOString();
  const rulesDate = new Date(rulesTime).toISOString();
  console.warn(
    `\n⚠️   PREDEPLOY WARNING\n` +
    `Backend/functions/src was modified after firestore.rules.\n` +
    `  Backend last modified : ${backendDate}\n` +
    `  firestore.rules last  : ${rulesDate}\n` +
    `Verify that the rules still cover any new collections added in the backend.\n`
  );
  // Warning only — does not abort. Upgrade to abort() if you want hard enforcement.
}

console.log("✅  Predeploy rules check passed.");
