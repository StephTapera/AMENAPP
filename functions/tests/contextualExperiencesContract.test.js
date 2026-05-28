"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const sourcePath = path.join(__dirname, "..", "contextualExperiences.js");
const indexPath = path.join(__dirname, "..", "index.js");
const rulesPath = path.join(__dirname, "..", "..", "AMENAPP", "firestore.deploy.rules");

test("contextual experience callables are exported", () => {
  const source = fs.readFileSync(sourcePath, "utf8");
  const index = fs.readFileSync(indexPath, "utf8");
  [
    "createContextualExperience",
    "updateContextualExperience",
    "publishContextualExperience",
    "unpublishContextualExperience",
    "archiveContextualExperience",
    "deleteContextualExperience",
    "joinContextualExperience",
    "leaveContextualExperience",
    "resolveContextualExperienceStack",
    "listOrganizationExperiences",
    "getContextualExperience",
    "createExperienceEvent",
    "createExperiencePrayerPrompt",
    "createExperienceDiscussion",
    "createExperienceMemory",
    "createExperienceTradition",
    "moderateExperienceContent",
    "reportExperienceContent",
    "updateExperienceNotificationSettings",
    "updateExperienceTheme",
    "getExperienceAnalytics",
    "manageExperienceRoles",
  ].forEach((name) => {
    assert.ok(source.includes(`exports.${name} =`), `${name} missing from contextualExperiences.js`);
    assert.ok(index.includes(`exports.${name} =`), `${name} missing from index.js`);
  });
});

test("contextual experience backend enforces auth, app check, roles, and privacy", () => {
  const source = fs.readFileSync(sourcePath, "utf8");
  assert.match(source, /enforceAppCheck: true/);
  assert.match(source, /auth-required/);
  assert.match(source, /requireManager/);
  assert.match(source, /requireModerator/);
  assert.match(source, /privatePrayerDefault/);
  assert.doesNotMatch(source, /body:\s*body,/);
});

test("firestore rules block client writes and protect tenant visibility", () => {
  const rules = fs.readFileSync(rulesPath, "utf8");
  assert.match(rules, /match\s*\/contextualExperiences/);
  assert.match(rules, /allow create\s*,\s*update\s*,\s*delete\s*:\s*if false/);
  assert.match(rules, /contextualExperienceVisible/);
  assert.match(rules, /contextualExperienceManager/);
  assert.match(rules, /match\s*\/contextualExperienceAuditLogs/);
  assert.match(rules, /match\s*\/contextualExperienceRateLimits/);
});
