"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const sourcePath = path.join(__dirname, "..", "spatialMessagesFunctions.js");
const indexPath = path.join(__dirname, "..", "index.js");
const rulesPath = path.join(__dirname, "..", "..", "AMENAPP", "firestore.deploy.rules");
const flagsPath = path.join(__dirname, "..", "..", "AMENAPP", "AMENFeatureFlags.swift");

test("spatial message callables are exported and guarded", () => {
  const source = fs.readFileSync(sourcePath, "utf8");
  const index = fs.readFileSync(indexPath, "utf8");
  [
    "createSharedViewingRoom",
    "joinSharedViewingRoom",
    "leaveSharedViewingRoom",
    "postAnchoredReply",
  ].forEach((name) => {
    assert.ok(source.includes(`exports.${name} =`), `${name} missing from spatialMessagesFunctions.js`);
    assert.ok(index.includes(`exports.${name} = spatialMessagesFns.${name}`), `${name} missing from index.js`);
  });
  assert.match(source, /enforceAppCheck: true/);
  assert.match(source, /unauthenticated/);
  assert.match(source, /checkRateLimit/);
  assert.match(source, /participantUids/);
});

test("spatial message rules are server-owned and feature flag defaults on", () => {
  const rules = fs.readFileSync(rulesPath, "utf8");
  const flags = fs.readFileSync(flagsPath, "utf8");
  assert.match(
      rules,
      /match\s*\/sharedViewingRooms\/\{document=\*\*\}\s*\{\s*allow read\s*:\s*if isAuthenticated\(\);?\s*allow write\s*:\s*if false;?\s*\}/,
  );
  assert.match(
      rules,
      /match\s*\/presenceSessions\/\{document=\*\*\}\s*\{\s*allow read\s*:\s*if isAuthenticated\(\);?\s*allow write\s*:\s*if false;?\s*\}/,
  );
  assert.match(flags, /sharedViewingRoomCallablesEnabled: Bool = true/);
  assert.match(flags, /"shared_viewing_room_callables_enabled": true as NSObject/);
});
