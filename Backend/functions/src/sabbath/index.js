/**
 * sabbath/index.js
 * Phase 2C — Backend (Sabbath Mode)
 *
 * Exports all Sabbath Mode callables and triggers for registration
 * in v2functions.js or the main index.ts.
 *
 * Callables (registered as Firebase HTTPS callables):
 *   - evaluateSabbathMode
 *   - setSabbathPreference
 *   - syncFamilySabbathPresence
 *
 * Trigger (Firestore background trigger — NOT a callable):
 *   - onSabbathNotificationWrite  (exported separately for v2functions registration)
 *
 * digestBuilder is an INTERNAL module only — do not export as a callable.
 */

"use strict";

const { evaluateSabbathMode } = require("./evaluateSabbathMode");
const { setSabbathPreference } = require("./setSabbathPreference");
const { syncFamilySabbathPresence } = require("./familySabbathSync");

// notificationBatcher is a Firestore trigger, not a callable — exported separately
const { onNotificationWrite } = require("./notificationBatcher");

module.exports = {
  evaluateSabbathMode,
  setSabbathPreference,
  syncFamilySabbathPresence,
  // Trigger: registered separately in v2functions so the function name
  // matches the Firebase Functions naming convention (onSabbathNotificationWrite)
  onSabbathNotificationWrite: onNotificationWrite,
};
