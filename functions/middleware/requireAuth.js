/**
 * middleware/requireAuth.js
 *
 * P1 FIX: Centralized authentication middleware for Cloud Functions.
 *
 * Before this, every onCall handler duplicated:
 *   if (!context.auth) throw new HttpsError('unauthenticated', ...)
 *
 * Replace that pattern with:
 *   const handler = requireAuth(async (request) => { ... });
 *   exports.myFunction = onCall({ region: REGION }, handler);
 *
 * Also provides:
 *   requireAuthWithRole(role) — for admin-only functions
 *   withStandardErrorHandling(fn) — wraps handler in a uniform try/catch
 *     that converts unknown errors to HttpsError('internal', ...) instead of
 *     leaking raw error messages to clients.
 */

'use strict';

const { HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const db = admin.firestore();

// ─────────────────────────────────────────────────────────────────────────────
// requireAuth
// Wraps an onCall handler. Throws 'unauthenticated' if request.auth is absent.
// Injects uid as the first argument after request for convenience.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @param {function(request, uid): Promise<any>} handler
 * @returns {function(request): Promise<any>}
 */
function requireAuth(handler) {
  return async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in to call this function.');
    }
    return handler(request, request.auth.uid);
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// requireAuthWithRole
// Throws 'permission-denied' if the user does not have the given custom claim.
// Useful for admin-only Cloud Functions (e.g. moderator dashboard writes).
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @param {string} role  Custom claim key, e.g. 'admin', 'moderator'
 * @param {function(request, uid): Promise<any>} handler
 * @returns {function(request): Promise<any>}
 */
function requireAuthWithRole(role, handler) {
  return async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    const claims = request.auth.token || {};
    if (!claims[role]) {
      throw new HttpsError(
        'permission-denied',
        `This function requires the '${role}' role.`
      );
    }
    return handler(request, request.auth.uid);
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// withStandardErrorHandling
// Wraps any handler in a try/catch that:
//   - re-throws HttpsError instances unchanged (they already have the right shape)
//   - converts all other errors to HttpsError('internal', ...) so raw stack
//     traces never reach the client, while still being logged server-side.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @param {function(request): Promise<any>} handler
 * @returns {function(request): Promise<any>}
 */
function withStandardErrorHandling(handler) {
  return async (request) => {
    try {
      return await handler(request);
    } catch (err) {
      // Re-throw structured Firebase errors as-is
      if (err instanceof HttpsError) throw err;
      // Log and convert unknown errors — never leak raw messages to clients
      console.error('[withStandardErrorHandling] Unexpected error:', err);
      throw new HttpsError('internal', 'An unexpected error occurred. Please try again.');
    }
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Composite helper: auth + error handling in one decorator
// Most callable functions should use this.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @param {function(request, uid): Promise<any>} handler
 * @returns {function(request): Promise<any>}
 */
function secureHandler(handler) {
  return withStandardErrorHandling(requireAuth(handler));
}

module.exports = { requireAuth, requireAuthWithRole, withStandardErrorHandling, secureHandler };
